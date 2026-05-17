#!/usr/bin/env bash
set -euo pipefail

MODE="${1:---build}"

case "$MODE" in
  --build|--minor|--major) ;;
  *)
    echo "用法:"
    echo "  bash scripts/bump_version.sh"
    echo "  bash scripts/bump_version.sh --build"
    echo "  bash scripts/bump_version.sh --minor"
    echo "  bash scripts/bump_version.sh --major"
    exit 1
    ;;
esac

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

python3 - "$REPO_ROOT" "$MODE" <<'PY'
import re
import sys
from pathlib import Path

repo_root = Path(sys.argv[1])
mode = sys.argv[2]
paths = [
    repo_root / "apps/ios-host/project.yml",
    repo_root / "apps/macos-menubar/project.yml",
]

build_re = re.compile(r'^(\s*CFBundleVersion:\s*)"?(\d+)"?(\s*)$', re.MULTILINE)
short_re = re.compile(r'^(\s*CFBundleShortVersionString:\s*)"?(\d+)\.(\d+)\.(\d+)"?(\s*)$', re.MULTILINE)

def replace_one(path: Path) -> None:
    text = path.read_text()
    build_match = build_re.search(text)
    short_match = short_re.search(text)
    if not build_match:
        raise SystemExit(f"Missing CFBundleVersion in {path}")
    if not short_match:
        raise SystemExit(f"Missing CFBundleShortVersionString in {path}")

    build = int(build_match.group(2))
    major, minor, patch = map(int, short_match.group(2, 3, 4))

    if mode == "--build":
        build += 1
    elif mode == "--minor":
        minor += 1
        patch = 0
        build = 1
    elif mode == "--major":
        major += 1
        minor = 0
        patch = 0
        build = 1

    text = build_re.sub(rf'\g<1>"{build}"\g<3>', text, count=1)
    text = short_re.sub(rf'\g<1>"{major}.{minor}.{patch}"\g<5>', text, count=1)
    path.write_text(text)

for path in paths:
    replace_one(path)
    print(f"updated {path.relative_to(repo_root)}")
PY

echo ""
if command -v git &>/dev/null && git -C "$REPO_ROOT" rev-parse --is-inside-work-tree &>/dev/null; then
  git -C "$REPO_ROOT" diff -- apps/ios-host/project.yml apps/macos-menubar/project.yml
else
  echo "git 不可用，已修改 project.yml。"
fi

echo ""
echo "修改未提交，请 review 后自行 git commit。"
