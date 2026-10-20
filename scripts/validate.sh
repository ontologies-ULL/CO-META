#!/usr/bin/env bash
# Validates the CO-META ontology and its individuals:
#   1. OWL 2 DL profile of the ontology, of each individuals file and of everything merged.
#   2. Consistency and class satisfiability of everything merged, with HermiT.
#   3. OWL tests: tests/owl/inconsistent/*.ttl must be inconsistent,
#      tests/owl/consistent/*.ttl must be consistent, and for each
#      tests/owl/inferences/<name>.ttl the ASK query <name>.rq must be true
#      once the inferred class and property assertions are added.
#   4. SHACL: the individuals and every tests/owl/consistent/*.ttl must conform
#      to SHACL/*.ttl, and every tests/shacl/invalid/*.ttl must violate them.
#
# Imports of CO-META and of its modules (imports/*.ttl) are resolved to the local
# files through catalog-v001.xml, so the published versions are never used.
#
# Requirements: Java 11+ and pyshacl (pip install pyshacl). ROBOT is downloaded
# into .tools/ on the first run. Set PYSHACL to use a pyshacl outside the PATH.
#
# Usage: scripts/validate.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CATALOG="$ROOT/catalog-v001.xml"
PYSHACL="${PYSHACL:-pyshacl}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { printf '  OK    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; failures=$((failures + 1)); }
show() { sed 's/^/        /' "$@" | head -n 30; }

robot() { "$ROOT/scripts/robot.sh" --catalog "$CATALOG" "$@"; }

if ! command -v "$PYSHACL" > /dev/null; then
    echo "pyshacl not found. Install it with: pip install pyshacl" >&2
    exit 2
fi

cd "$ROOT"
mapfile -t INDIVIDUALS < <(find individuals -name '*.ttl' | sort)
ALL_INPUTS=(--input CO-META.ttl)
for f in "${INDIVIDUALS[@]}"; do ALL_INPUTS+=(--input "$f"); done

echo "1. OWL 2 DL profile"
check_profile() {
    local label="$1"
    shift
    if robot merge "$@" validate-profile --profile DL --output "$TMP/profile.txt" > "$TMP/robot.log" 2>&1; then
        pass "$label"
    else
        fail "$label"
        show "$TMP/profile.txt" "$TMP/robot.log"
    fi
}
for f in imports/*.ttl; do check_profile "$f" --input "$f"; done
check_profile "CO-META.ttl" --input CO-META.ttl
for f in "${INDIVIDUALS[@]}"; do check_profile "$f" --input "$f"; done
check_profile "everything merged" "${ALL_INPUTS[@]}"

echo "2. Consistency of everything merged (HermiT)"
robot merge "${ALL_INPUTS[@]}" --output "$TMP/all.ttl" > "$TMP/robot.log" 2>&1 || { show "$TMP/robot.log"; exit 1; }
if robot reason --input "$TMP/all.ttl" --reasoner HermiT --equivalent-classes-allowed all \
        --output "$TMP/reasoned.ttl" > "$TMP/robot.log" 2>&1; then
    pass "consistent, no unsatisfiable classes"
else
    fail "inconsistent or with unsatisfiable classes"
    show "$TMP/robot.log"
fi

echo "3. OWL tests"
for f in tests/owl/inconsistent/*.ttl; do
    if robot reason --input "$f" --reasoner HermiT --output "$TMP/test.ttl" > "$TMP/robot.log" 2>&1; then
        fail "$f (expected inconsistent, but it is consistent)"
    elif grep -qi "inconsistent" "$TMP/robot.log"; then
        pass "$f"
    else
        fail "$f (expected inconsistent, but ROBOT failed for another reason)"
        show "$TMP/robot.log"
    fi
done
for f in tests/owl/consistent/*.ttl; do
    if robot reason --input "$f" --reasoner HermiT --output "$TMP/test.ttl" > "$TMP/robot.log" 2>&1; then
        pass "$f"
    else
        fail "$f (expected consistent)"
        show "$TMP/robot.log"
    fi
done
for f in tests/owl/inferences/*.ttl; do
    if robot reason --input "$f" --reasoner HermiT --axiom-generators "ClassAssertion PropertyAssertion" \
            --include-indirect true --output "$TMP/test.ttl" > "$TMP/robot.log" 2>&1 \
        && robot query --input "$TMP/test.ttl" --query "${f%.ttl}.rq" "$TMP/ask.txt" > "$TMP/robot.log" 2>&1; then
        if grep -qx "true" "$TMP/ask.txt"; then
            pass "$f"
        else
            fail "$f (the expected inferences in ${f%.ttl}.rq do not hold)"
        fi
    else
        fail "$f (reasoning or query failed)"
        show "$TMP/robot.log"
    fi
done

echo "4. SHACL"
for f in SHACL/*.ttl; do cat "$f"; echo; done > "$TMP/shapes.ttl"
# Exit status: 0 conforms, 1 violates the shapes, 2 or more an error. pyshacl also exits
# with 1 when a shape itself is malformed ("Validation Failure"), which is an error.
shacl() {
    local status=0
    "$PYSHACL" --shacl "$TMP/shapes.ttl" --data-file-format turtle "$1" > "$TMP/shacl.log" 2>&1 || status=$?
    if grep -q "Validation Failure" "$TMP/shacl.log"; then status=2; fi
    return $status
}
status=0
shacl "$TMP/all.ttl" || status=$?
case $status in
    0) pass "individuals conform to SHACL/*.ttl" ;;
    1) fail "individuals violate SHACL/*.ttl"; show "$TMP/shacl.log" ;;
    *) fail "pyshacl error"; show "$TMP/shacl.log" ;;
esac
for f in tests/owl/consistent/*.ttl; do
    robot merge --input "$f" --output "$TMP/test.ttl" > "$TMP/robot.log" 2>&1 || { fail "$f (merge failed)"; show "$TMP/robot.log"; continue; }
    status=0
    shacl "$TMP/test.ttl" || status=$?
    case $status in
        0) pass "$f" ;;
        1) fail "$f (expected to conform to SHACL)"; show "$TMP/shacl.log" ;;
        *) fail "$f (pyshacl error)"; show "$TMP/shacl.log" ;;
    esac
done
for f in tests/shacl/invalid/*.ttl; do
    robot merge --input "$f" --output "$TMP/test.ttl" > "$TMP/robot.log" 2>&1 || { fail "$f (merge failed)"; show "$TMP/robot.log"; continue; }
    status=0
    shacl "$TMP/test.ttl" || status=$?
    case $status in
        1) pass "$f" ;;
        0) fail "$f (expected a SHACL violation, but it conforms)" ;;
        *) fail "$f (pyshacl error)"; show "$TMP/shacl.log" ;;
    esac
done

echo
if [ "$failures" -gt 0 ]; then
    echo "$failures check(s) failed."
    exit 1
fi
echo "All checks passed."
