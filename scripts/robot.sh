#!/usr/bin/env bash
# Runs ROBOT (http://robot.obolibrary.org) with the given arguments, downloading the
# pinned version into .tools/ on the first run. Requires Java 11+.
#
# Usage: scripts/robot.sh <robot arguments>
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROBOT_VERSION="1.9.11"
ROBOT_JAR="$ROOT/.tools/robot-$ROBOT_VERSION.jar"

if [ ! -f "$ROBOT_JAR" ]; then
    echo "Downloading ROBOT $ROBOT_VERSION..." >&2
    mkdir -p "$ROOT/.tools"
    curl -sSfL -o "$ROBOT_JAR.part" \
        "https://github.com/ontodev/robot/releases/download/v$ROBOT_VERSION/robot.jar"
    mv "$ROBOT_JAR.part" "$ROBOT_JAR"
fi

exec java -jar "$ROBOT_JAR" "$@"
