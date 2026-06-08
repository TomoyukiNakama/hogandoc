# CLAUDE.md — hogandoc リリース管理ガイド

このファイルは Claude（および人間のメンテナ）がこのリポジトリで作業するための運用ガイドです。

## このリポジトリの目的

図形編集ソフトウェア **hogandoc** の**配布物（ビルド済みバイナリ）を管理・公開する**ための専用リポジトリです。

- アプリ本体のソースコードは**ここには含まれません**（別管理）。
- このリポジトリの役割は、各 OS 向けのビルド成果物を受け取り、GitHub Release として公開すること。
- 公開リポジトリ: `TomoyukiNakama/hogandoc`（`origin` = `https://github.com/TomoyukiNakama/hogandoc.git`）

## 重要な原則：バイナリは Git にコミットしない

巨大なバイナリ（合計約 100MB）は **Git 本体にはコミットしません**。配布は必ず **GitHub Release の添付ファイル**として行います。`.gitignore` で以下を除外済み：`*.zip` / `*.AppImage` / `*.dmg` / `*.msi` / `/dist/`。

Git で管理するのは運用ファイルのみ：`README.md` / `CLAUDE.md` / `CHANGELOG.md` / `.gitignore` / `scripts/`。

## 配布物レイアウト

ビルド側からは OS ごとに zip が渡されます。中身を**展開して**、素のインストーラ／実行ファイルを Release に添付します。

| OS | 配布資産（Release 添付ファイル名） | 取り出し元 zip |
|----|----------------------------------|----------------|
| Linux | `hogandoc-linux-x86_64.AppImage` | `hogandoc-linux.zip` |
| macOS (Apple Silicon) | `hogandoc-macos-arm64.dmg` | `hogandoc-macos.zip` |
| Windows | `hogandoc-windows-x86_64.msi` | `hogandoc-windows.zip` |
| Windows | `hogandoc-windows-x86_64.zip` | `hogandoc-windows.zip` |

→ 1 リリースあたり **4 つの資産**を添付する。

## バージョン規約

- [セマンティックバージョニング](https://semver.org/lang/ja/)に従う。
- Git タグは `vX.Y.Z` 形式（例：`v0.1.0`）。
- 初回リリースは **`v0.1.0`**。

## リリース手順

### 推奨：スクリプトを使う

1. ビルド側から渡された 3 つの zip（`hogandoc-linux.zip` / `hogandoc-macos.zip` / `hogandoc-windows.zip`）をリポジトリ直下に置く。
2. `CHANGELOG.md` に当該バージョンの節を追記する。
3. スクリプトを実行：

   ```bash
   bash scripts/release.sh v0.1.0
   ```

   スクリプトは「zip を `dist/` に展開 → 4 資産の存在確認 → Git タグ作成・push → `gh release create`（CHANGELOG の該当節を本文に使用）」を行う。

### 手動で行う場合

```bash
# 1. zip を dist/ に展開
mkdir -p dist
unzip -o hogandoc-linux.zip   -d dist
unzip -o hogandoc-macos.zip   -d dist
unzip -o hogandoc-windows.zip -d dist

# 2. タグを作成して push
git tag v0.1.0
git push origin v0.1.0

# 3. Release を作成（4 資産を添付）
gh release create v0.1.0 \
  --title "hogandoc v0.1.0" \
  --notes-file <(...CHANGELOG の該当節...) \
  dist/hogandoc-linux-x86_64.AppImage \
  dist/hogandoc-macos-arm64.dmg \
  dist/hogandoc-windows-x86_64.msi \
  dist/hogandoc-windows-x86_64.zip
```

### 既存リリースに資産を追加し直す場合

```bash
gh release upload v0.1.0 dist/<asset> --clobber
```

## リリースノートの書き方

- 変更内容は `CHANGELOG.md`（Keep a Changelog 形式）に記録する。
- Release 本文には該当バージョンの節を流用する。

## 前提環境

- `gh` CLI が認証済みであること（アカウント：`TomoyukiNakama`）。確認：`gh auth status`
- README のダウンロードリンクは GitHub の latest エイリアス（`/releases/latest/download/<asset>`）を使うため、**資産名を変えるとリンクが切れる**点に注意。資産名を変更する場合は README も更新する。

## 外部公開アクションの扱い

`gh release create` / `git push` / タグ push は**外部公開**を伴い取り消しコストがあるため、実行前にユーザーの承認を得ること。
