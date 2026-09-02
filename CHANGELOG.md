# Changelog

このプロジェクトの主な変更点を記録します。書式は [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) に、バージョン番号は [Semantic Versioning](https://semver.org/lang/ja/) に従います。

## [0.3.3] - 2026-09-02

### Added
- 複数選択の整列: グリッドに合わせた等間隔整列、近接して縦 / 横に並べる。
- 複数選択時にプロパティパネルで幅・高さ、フォント（サイズ・色・ファミリー）を一括編集。
- 隣接する四角形の複数選択を 1 つの表にまとめる「表にする」。
- Windows / macOS でも表のコピーを Excel のセルとして貼り付け可能に。
- ローカル API（`127.0.0.1:7420`）の JSON Schema を `GET /api/v1/schema` と skill に同梱して公開。
- AI エージェント向け skill `hogandoc-editor-api` を `skills/` と Release アセット `hogandoc-editor-api-skill.zip` で配布。

## [0.2.0] - 2026-07-05

### Added
- DrawingML 対応。各 OS 向けバイナリ（Windows .msi / .zip、macOS .dmg、Linux .AppImage）を再ビルドして更新。

## [0.1.7] - 2026-06-21

### Changed
- メンテナンスビルド。各 OS 向けバイナリ（Windows .msi / .zip、macOS .dmg、Linux .AppImage）を再ビルドして更新。

## [0.1.3] - 2026-06-14

### Changed
- メンテナンスビルド。各 OS 向けバイナリ（Windows .msi / .zip、macOS .dmg、Linux .AppImage）を再ビルドして更新。

## [0.1.2] - 2026-06-11

### Changed
- メンテナンスビルド。各 OS 向けバイナリ（Windows .msi / .zip、macOS .dmg、Linux .AppImage）を再ビルドして更新。

## [0.1.1] - 2026-06-09

### Changed
- メンテナンスビルド。各 OS 向けバイナリ（Windows .msi / .zip、macOS .dmg、Linux .AppImage）を再ビルドして更新。

## [0.1.0] - 2026-06-08

### Added
- hogandoc の初回リリース。Windows (.msi / .zip) / macOS (.dmg) / Linux (.AppImage) 向けバイナリを配布。
