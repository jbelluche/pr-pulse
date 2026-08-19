#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
"$repo_dir/Scripts/package_app.sh"
pkill -x PRPulse 2>/dev/null || true
open -n "$repo_dir/PRPulse.app"
