#!/usr/bin/env bash
set -euo pipefail
exec "$(dirname "$0")/BUILD_ANDROID.sh" "$@"
