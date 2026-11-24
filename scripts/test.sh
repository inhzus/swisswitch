#!/usr/bin/env bash
# Runs `swift test`. The Command Line Tools ship the Swift Testing macro plugin in a
# subfolder that SwiftPM doesn't search by default, so point the compiler at it.
set -euo pipefail

cd "$(dirname "$0")/.."

PLUGINS="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing"
if [[ -d "$PLUGINS" ]]; then
    exec swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@"
fi
exec swift test "$@"
