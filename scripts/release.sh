#!/usr/bin/env bash
#
# hogandoc リリース補助スクリプト
#
# 使い方:
#   bash scripts/release.sh <version>
#   例: bash scripts/release.sh v0.1.0
#
# 動作:
#   1. リポジトリ直下の 3 つの zip を dist/ に展開
#   2. 4 つの配布資産が揃っているか確認
#   3. Git タグを作成して push
#   4. gh release create で Release を作成し、4 資産を添付
#      （CHANGELOG.md に該当バージョンの節があれば本文に使用）
#
# 前提: gh CLI が認証済みであること（gh auth status）
#
set -euo pipefail

# --- 引数チェック ---------------------------------------------------------
if [[ $# -ne 1 ]]; then
  echo "usage: bash scripts/release.sh <version>   (例: v0.1.0)" >&2
  exit 1
fi

VERSION="$1"
if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: バージョンは vX.Y.Z 形式で指定してください（例: v0.1.0）。指定値: $VERSION" >&2
  exit 1
fi

# リポジトリルートへ移動（このスクリプトの 1 つ上の階層）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

DIST="dist"

# 配布元 zip と、展開後に存在すべき資産
SRC_ZIPS=(hogandoc-linux.zip hogandoc-macos.zip hogandoc-windows.zip)
ASSETS=(
  "hogandoc-linux-x86_64.AppImage"
  "hogandoc-macos-arm64.dmg"
  "hogandoc-windows-x86_64.msi"
  "hogandoc-windows-x86_64.zip"
)

# --- 1. zip の存在確認 ----------------------------------------------------
for z in "${SRC_ZIPS[@]}"; do
  if [[ ! -f "$z" ]]; then
    echo "error: $z が見つかりません。3 つの zip をリポジトリ直下に置いてください。" >&2
    exit 1
  fi
done

# --- 2. dist/ に展開 ------------------------------------------------------
echo "==> zip を $DIST/ に展開します"
rm -rf "$DIST"
mkdir -p "$DIST"
for z in "${SRC_ZIPS[@]}"; do
  echo "    unzip $z"
  unzip -o -q "$z" -d "$DIST"
done

# --- 3. 資産の存在確認 ----------------------------------------------------
ASSET_PATHS=()
for a in "${ASSETS[@]}"; do
  if [[ ! -f "$DIST/$a" ]]; then
    echo "error: 展開後に $DIST/$a が見つかりません。zip の中身を確認してください。" >&2
    echo "       展開された内容:" >&2
    ls -la "$DIST" >&2
    exit 1
  fi
  ASSET_PATHS+=("$DIST/$a")
done
echo "==> 4 つの配布資産を確認しました"

# --- 4. リリースノートの準備 ----------------------------------------------
NOTES_ARGS=()
NOTES_FILE=""
NUM="${VERSION#v}"   # 先頭の v を除いた X.Y.Z
if [[ -f CHANGELOG.md ]] && grep -q "^## \[$NUM\]" CHANGELOG.md; then
  NOTES_FILE="$(mktemp)"
  # 該当バージョンの節（次の "## [" 見出しの直前まで）を抽出
  awk -v ver="$NUM" '
    $0 ~ "^## \\[" ver "\\]" { inblock=1; next }
    inblock && /^## \[/      { exit }
    inblock                  { print }
  ' CHANGELOG.md > "$NOTES_FILE"
  NOTES_ARGS=(--notes-file "$NOTES_FILE")
  echo "==> CHANGELOG.md から $NUM の節をリリースノートに使用します"
else
  NOTES_ARGS=(--generate-notes)
  echo "==> CHANGELOG.md に $NUM の節がないため、自動生成ノートを使用します"
fi

# --- 5. タグ作成 & push ---------------------------------------------------
if git rev-parse "$VERSION" >/dev/null 2>&1; then
  echo "==> タグ $VERSION は既に存在します（作成をスキップ）"
else
  echo "==> タグ $VERSION を作成して push します"
  git tag "$VERSION"
  git push origin "$VERSION"
fi

# --- 6. Release 作成 ------------------------------------------------------
echo "==> gh release create $VERSION"
gh release create "$VERSION" \
  --title "hogandoc $VERSION" \
  "${NOTES_ARGS[@]}" \
  "${ASSET_PATHS[@]}"

[[ -n "$NOTES_FILE" ]] && rm -f "$NOTES_FILE"

echo "==> 完了: $VERSION のリリースを作成しました"
gh release view "$VERSION"
