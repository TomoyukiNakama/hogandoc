# hogandoc

**日本語** | [English](#english)

図形編集ソフトウェア **hogandoc** の配布リポジトリです。Windows / macOS / Linux 向けのビルド済みバイナリを GitHub Release で公開しています。

## スクリーンショット

![hogandoc スクリーンショット](docs/images/screenshot-01.png)

## 機能

Microsoft OfficeのOpen XMLベースの図形(DrawingML)がアプリケーション内で利用できるようになりました。ExcelやWordで作成した図形をコピーしてhogandocに貼り付けすることができます。

## ダウンロード

最新版は以下から入手できます（常に最新リリースを指します）。

| OS | ダウンロード |
|----|-------------|
| Windows (x86_64) | [インストーラ (.msi)](https://github.com/TomoyukiNakama/hogandoc/releases/latest/download/hogandoc-windows-x86_64.msi) / [zip](https://github.com/TomoyukiNakama/hogandoc/releases/latest/download/hogandoc-windows-x86_64.zip) |
| macOS (Apple Silicon) | [.dmg](https://github.com/TomoyukiNakama/hogandoc/releases/latest/download/hogandoc-macos-arm64.dmg) |
| Linux (x86_64) | [.AppImage](https://github.com/TomoyukiNakama/hogandoc/releases/latest/download/hogandoc-linux-x86_64.AppImage) |

過去のバージョンは [Releases ページ](https://github.com/TomoyukiNakama/hogandoc/releases) を参照してください。

## インストール手順

### Windows
- `.msi` をダブルクリックしてインストーラを実行する。または `.zip` を展開して実行ファイルを直接起動する。

### macOS (Apple Silicon)
- `.dmg` をマウントし、アプリを「アプリケーション」フォルダにドラッグする。
- 初回起動時に Gatekeeper の警告が出る場合は、右クリック →「開く」で起動する。

### Linux
- `.AppImage` に実行権限を付与して起動する：
  ```bash
  chmod +x hogandoc-linux-x86_64.AppImage
  ./hogandoc-linux-x86_64.AppImage
  ```

## AI エージェント連携（skill）

hogandoc は起動中に `127.0.0.1:7420` でローカル API（REST / WebSocket）を提供しており、Claude Code などの AI エージェントから開いている文書を読み書き・描画確認できます（設定で「ローカル API サーバー」を有効にしてください。同じ PC・同じユーザーからのみ接続可能です）。

そのための前提知識をまとめた skill `hogandoc-editor-api` を [`skills/hogandoc-editor-api/`](skills/hogandoc-editor-api/) で配布しています（プロトコル仕様・JSON Schema・Op の例を同梱）。

導入方法（いずれか）:

- skills CLI: `npx skills add TomoyukiNakama/hogandoc`
- Claude Code: `skills/hogandoc-editor-api/` をプロジェクトの `.claude/skills/` か `~/.claude/skills/` にコピー
- zip: 最新リリースの [`hogandoc-editor-api-skill.zip`](https://github.com/TomoyukiNakama/hogandoc/releases/latest/download/hogandoc-editor-api-skill.zip) を展開して同様に配置

skill はエディタのリリースごとに更新されます（`references/VERSION` に対応バージョンを記載）。

## ライセンス

本ソフトウェアはプロプライエタリ（独自ライセンス）です。詳細は [LICENSE](LICENSE) を参照してください。
Copyright (c) 2026 Tomoyuki Nakama. All rights reserved.

---

## English

This is the distribution repository for **hogandoc**, a shape/diagram editing application. Prebuilt binaries for Windows / macOS / Linux are published as GitHub Releases.

> ℹ️ Add a description of hogandoc's features here. This repository contains distribution artifacts only.

### Screenshot

![hogandoc screenshot](docs/images/screenshot-01.png)

### Download

Always points to the latest release:

| OS | Download |
|----|----------|
| Windows (x86_64) | [Installer (.msi)](https://github.com/TomoyukiNakama/hogandoc/releases/latest/download/hogandoc-windows-x86_64.msi) / [zip](https://github.com/TomoyukiNakama/hogandoc/releases/latest/download/hogandoc-windows-x86_64.zip) |
| macOS (Apple Silicon) | [.dmg](https://github.com/TomoyukiNakama/hogandoc/releases/latest/download/hogandoc-macos-arm64.dmg) |
| Linux (x86_64) | [.AppImage](https://github.com/TomoyukiNakama/hogandoc/releases/latest/download/hogandoc-linux-x86_64.AppImage) |

See the [Releases page](https://github.com/TomoyukiNakama/hogandoc/releases) for previous versions.

### Installation

- **Windows**: Run the `.msi` installer, or extract the `.zip` and launch the executable directly.
- **macOS (Apple Silicon)**: Open the `.dmg` and drag the app into Applications. On first launch, if Gatekeeper blocks it, right-click → Open.
- **Linux**: Make the AppImage executable and run it:
  ```bash
  chmod +x hogandoc-linux-x86_64.AppImage
  ./hogandoc-linux-x86_64.AppImage
  ```

### AI agent integration (skill)

While running, hogandoc serves a local API (REST / WebSocket) on `127.0.0.1:7420` so AI agents such as Claude Code can read and edit the open document and render it to PNG for verification (enable "local API server" in Settings; only processes on the same machine and user can connect).

The `hogandoc-editor-api` skill in [`skills/hogandoc-editor-api/`](skills/hogandoc-editor-api/) bundles everything an agent needs: the protocol spec, JSON Schema and tested Op examples.

Install with one of:

- skills CLI: `npx skills add TomoyukiNakama/hogandoc`
- Claude Code: copy `skills/hogandoc-editor-api/` into your project's `.claude/skills/` or `~/.claude/skills/`
- zip: extract [`hogandoc-editor-api-skill.zip`](https://github.com/TomoyukiNakama/hogandoc/releases/latest/download/hogandoc-editor-api-skill.zip) from the latest release and place it the same way

The skill is refreshed on every editor release (`references/VERSION` names the matching version).

### License

This software is proprietary. See [LICENSE](LICENSE) for details.
Copyright (c) 2026 Tomoyuki Nakama. All rights reserved.
