#!/usr/bin/env bash
set -euo pipefail
exec "$(dirname "$0")/tool/build_android.sh" "$@"
