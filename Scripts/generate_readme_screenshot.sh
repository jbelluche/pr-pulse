#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
cd "$repo_dir"

output_path="${1:-$repo_dir/docs/pr-pulse-demo.png}"
demo_user="${PR_PULSE_SCREENSHOT_USER:-}"

if [[ -z "$demo_user" ]]; then
    demo_user="$(gh api user --jq .login)"
fi

swift run -c release PRPulse \
    --generate-readme-screenshot "$output_path" \
    --demo-user "$demo_user"
