#!/bin/bash
# 把当前工作树导出到孤儿分支 public（不带历史、不带私人文件），推到 GitHub 用。
# 用法：bash scripts/publish.sh "提交说明"；之后 git push origin public:main
set -e
cd "$(dirname "$0")/.."
MSG=${1:-"Update"}
EXPORT=$(mktemp -d)
trap 'rm -rf "$EXPORT"; git worktree remove --force "$EXPORT.wt" 2>/dev/null; git worktree prune' EXIT
rsync -a --delete \
  --exclude .git --exclude .build --exclude 'app/.build' --exclude 'app/Reverie.app' \
  --exclude mediaremote-adapter --exclude 'design/directions/.build' --exclude 'design/directions/v1' \
  --exclude 'design/directions/out' --exclude docs/roundtable --exclude AGENTS.md --exclude CODEX_HANDOFF.md \
  --exclude nowplaying_test --exclude nowplaying_test.swift --exclude .DS_Store --exclude '.claude' \
  --exclude 'app/Resources/ReverieIcon1024.tiff' \
  ./ "$EXPORT/"
# CLAUDE.md：去掉共享记忆那一节和本机路径；CHANGELOG：本机路径改成 ~。
python3 - "$EXPORT" <<'PY'
import re, sys, os
root = sys.argv[1]
home = os.path.expanduser("~")
repo = os.getcwd()
p = os.path.join(root, "CLAUDE.md")
s = open(p).read()
s = re.sub(r"\n## Obsidian 共享项目记忆.*", "\n", s, flags=re.S)
s = s.replace(repo, "<repo>").replace(home, "~")
open(p, "w").write(s)
for name in ["CHANGELOG.md", "README.md"]:
    p = os.path.join(root, name)
    if os.path.exists(p):
        s = open(p).read().replace(repo, "<repo>").replace(home, "~")
        s = re.sub(r"~/Documents/RuruCode/备份/", "<backup>/", s)
        open(p, "w").write(s)
PY
if git show-ref --verify --quiet refs/heads/public; then
  git worktree add -q "$EXPORT.wt" public
else
  git worktree add -q --detach "$EXPORT.wt"
  (cd "$EXPORT.wt" && git checkout -q --orphan public && git rm -rfq . >/dev/null 2>&1 || true)
fi
rsync -a --delete --exclude .git "$EXPORT/" "$EXPORT.wt/"
# 公开提交的署名：默认用 main 上最后一次提交的名字，邮箱建议用 GitHub 的 noreply（PUBLISH_EMAIL）。
export GIT_AUTHOR_NAME=${PUBLISH_NAME:-$(git log -1 --format=%an main)}
export GIT_COMMITTER_NAME=$GIT_AUTHOR_NAME
export GIT_AUTHOR_EMAIL=${PUBLISH_EMAIL:-$(git log -1 --format=%ae main)}
export GIT_COMMITTER_EMAIL=$GIT_AUTHOR_EMAIL
(cd "$EXPORT.wt" && git add -A && git commit -q -m "$MSG" && git log --oneline -1)
git worktree remove --force "$EXPORT.wt"
echo "分支 public 已更新；推送：git push origin public:main"
