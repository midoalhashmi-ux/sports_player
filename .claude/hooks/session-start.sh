#!/bin/bash
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

if ! command -v headroom >/dev/null 2>&1; then
  if command -v uv >/dev/null 2>&1; then
    uv tool install --python 3.13 headroom-ai
  else
    pip3 install --user headroom-ai
  fi
fi

export PATH="$HOME/.local/bin:$PATH"
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$CLAUDE_ENV_FILE"
fi

headroom doctor || true
