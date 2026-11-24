#!/bin/sh
# Command Line Tools ship the Swift Testing macro plugin in a subfolder that
# SwiftPM doesn't search by default, so point the compiler at it.
set -e
cd "$(dirname "$0")/.."
PLUGINS="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing"
exec swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@"
