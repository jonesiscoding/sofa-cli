#!/bin/bash

# Exit Codes
exitNoJQ=2

# Locate JQ
[ -z "$JQ_BIN" ] &&
  JQ_BIN=$(whereis -B /usr/bin /usr/local/bin /opt/homebrew/bin /opt/local/bin "$HOME/local/.bin" -f jq | awk '{print $2}')
function assert::jq() {
  local file

  [ -z "$JQ_BIN" ] &&
    JQ_BIN="$(d="/usr/local/bin"; test -w "$d" && echo "$d" || echo "$HOME/.local/bin")/jq"

  [ ! -f "$JQ_BIN" ] && [ "$JQ_BIN" != "/usr/bin/jq" ] &&
    mkdir -p "$(dirname "$JQ_BIN")" &&
    file="jq-$(uname -s | sed 's/Darwin/macos/; s/L/l/')-$(uname -m | sed 's/x86_/amd/; s/aarch/arm/')" &&
    curl -s -L -o "$JQ_BIN" "https://github.com/jqlang/jq/releases/latest/download/$file" &&
    chmod 755 "$JQ_BIN"

  [ ! -f "$JQ_BIN" ] &&
    >&2 echo "ERROR: JQ_BIN=$JQ_BIN, but 'jq' executable was not found." && return "$exitNoJQ"

  return 0
}