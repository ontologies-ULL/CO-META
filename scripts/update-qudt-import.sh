#!/usr/bin/env bash
# Regenerates imports/qudt.ttl, the module with the QUDT terms that CO-META aligns with.
#
# QUDT is not in the OWL 2 DL profile, so it cannot be imported as a whole. The terms
# are extracted with MIREOT: only their declaration, rdfs:label and class hierarchy up
# to qudt:StructuredDatatype are kept, which is enough to use them as superclasses.
#
# To update QUDT or add terms, change QUDT_VERSION or TERMS, rerun this script and
# then scripts/validate.sh.
#
# Usage: scripts/update-qudt-import.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
QUDT_VERSION="3.5.2"
SOURCE="https://qudt.org/$QUDT_VERSION/schema/datatype"
MODULE_IRI="https://w3id.org/ontologies-ULL/CO-META/imports/qudt"
QUDT="http://qudt.org/schema/qudt/"
TERMS=(Collection Sequence Set MultiSet Matrix Table Record)
UPPER_TERM="StructuredDatatype"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading QUDT $QUDT_VERSION datatypes..."
curl -sSfL -H "Accept: text/turtle" -o "$TMP/datatype.ttl" "$SOURCE"
printf "$QUDT%s\n" "${TERMS[@]}" > "$TMP/lower.txt"
printf "$QUDT%s\n" "$UPPER_TERM" > "$TMP/upper.txt"

mkdir -p "$ROOT/imports"
"$ROOT/scripts/robot.sh" \
    extract --input "$TMP/datatype.ttl" --method MIREOT \
            --lower-terms "$TMP/lower.txt" --upper-terms "$TMP/upper.txt" \
    remove --select annotation-properties --exclude-term http://www.w3.org/2000/01/rdf-schema#label \
    annotate --ontology-iri "$MODULE_IRI" \
             --version-iri "$MODULE_IRI/$QUDT_VERSION" \
             --link-annotation http://purl.org/dc/terms/source "$SOURCE" \
             --language-annotation http://www.w3.org/2000/01/rdf-schema#comment \
                 "QUDT $QUDT_VERSION datatype terms used by CO-META, extracted with MIREOT by scripts/update-qudt-import.sh. Do not edit by hand." en \
             --add-prefix "qudt: $QUDT" --add-prefix "dcterms: http://purl.org/dc/terms/" \
             --output "$ROOT/imports/qudt.ttl"
echo "Written imports/qudt.ttl"
