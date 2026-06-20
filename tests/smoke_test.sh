#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib/assert.sh"

# The plugin manifest must exist and declare the plugin name.
manifest="$DIR/../.claude-plugin/plugin.json"
[ -f "$manifest" ] && content="$(cat "$manifest")" || content=""
assert_contains "$content" '"name": "superafk"' "plugin.json declares name superafk"

assert_report || exit 1
