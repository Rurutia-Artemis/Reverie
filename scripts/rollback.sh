#!/bin/bash
set -euo pipefail
if [[ $# -gt 1 ]]; then
    echo 'Usage: rollback.sh [backup.app]' >&2
    exit 2
fi
script_dir=$(cd "$(dirname "$0")" && pwd)
backup=${1:-${REVERIE_BACKUP:-}}
if [[ -z $backup ]]; then
    echo "用法: rollback.sh <备份的 Reverie.app 路径>（或设 REVERIE_BACKUP）" >&2
    exit 2
fi
exec /bin/bash "$script_dir/deploy.sh" "$backup"
