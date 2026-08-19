#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
demo_user="${PR_PULSE_DEMO_USER:-demo-user}"

"$repo_dir/Scripts/package_app.sh"
pkill -x PRPulse 2>/dev/null || true
open -n "$repo_dir/PRPulse.app" --args \
    --demo-data \
    --demo-user "$demo_user"

echo "PR Pulse is running with isolated demo data."
