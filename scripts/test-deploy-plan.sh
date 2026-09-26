#!/bin/bash
set -euo pipefail
script_dir=$(cd "$(dirname "$0")" && pwd)
actual=$(mktemp "${TMPDIR:-/tmp}/reverie-plan.XXXXXX")
trap 'rm -f "$actual"' EXIT
count=0
for loaded in 0 1; do
    for disabled in 0 1; do
        for running in 0 1; do
            state="loaded=$loaded,disabled=$disabled,running=$running"
            for path in success place health; do
                printf '# original %s; path %s\n' "$state" "$path" >> "$actual"
                args=("$script_dir/deploy.sh" '/nonexistent/candidate.app' --plan-only --state "$state")
                if [[ $path != success ]]; then args+=(--fail-at "$path"); fi
                /bin/bash "${args[@]}" >> "$actual"
                count=$((count + 1))
            done
        done
    done
done
state=loaded=0,disabled=0,running=0
printf '# original %s; path health; --enable-autostart\n' "$state" >> "$actual"
/bin/bash "$script_dir/deploy.sh" '/nonexistent/candidate.app' --enable-autostart \
    --plan-only --state "$state" --fail-at health >> "$actual"
count=$((count + 1))
# Static, independently derived oracle. Never regenerate it from deploy.sh output.
diff -u "$script_dir/deploy-plan.expected" "$actual"
echo "PASS: $count deployment plan cases"
