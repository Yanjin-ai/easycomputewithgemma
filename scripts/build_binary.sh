#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CP_DIR="$REPO_ROOT/services/control-plane"

echo "Building control plane binary..."
cd "$CP_DIR"

# @yao-pkg/pkg is installed as a devDependency; no global install needed.

npm install
npm run build:binary

BINARY="$CP_DIR/dist-bin/gemma4all-cp-macos"
if [[ -f "$BINARY" ]]; then
  echo "✓ Binary built: $BINARY ($(du -sh "$BINARY" | cut -f1))"

  # Copy better_sqlite3.node to dist-bin/ for runtime native loading.
  SQLITE_NODE="$CP_DIR/node_modules/better-sqlite3/build/Release/better_sqlite3.node"
  if [[ -f "$SQLITE_NODE" ]]; then
    cp "$SQLITE_NODE" "$CP_DIR/dist-bin/"
    echo "✓ Copied better_sqlite3.node to dist-bin/"
  fi

  # Copy JSON schemas next to the binary so schemaValidator can locate them.
  SCHEMAS_DIR="$REPO_ROOT/packages/schemas"
  if [[ -d "$SCHEMAS_DIR" ]]; then
    rm -rf "$CP_DIR/dist-bin/schemas"
    cp -r "$SCHEMAS_DIR" "$CP_DIR/dist-bin/schemas"
    echo "✓ Copied packages/schemas to dist-bin/schemas/ ($(ls "$CP_DIR/dist-bin/schemas"/*.json 2>/dev/null | wc -l | tr -d ' ') files)"
  fi
else
  echo "✗ Build failed"
  exit 1
fi
