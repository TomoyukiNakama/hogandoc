---
name: hogandoc-editor-api
description: 起動中の hogandoc-editor（デスクトップ版）が開いている文書を、内蔵ローカル API（127.0.0.1、collab/v1）経由で読む・図形を追加/変更する・入力フィールドを埋める・PNG で描画確認する・保存するときに使用。hogandoc-server（Web ホスティング側）の API ではない。
---

## Overview

hogandoc-editor は起動時に `127.0.0.1:{port}`（既定 7420）で REST + WebSocket の
ローカル API を立てる（設定 `collab_local_server_enabled` が true のとき）。
同じマシン・同じユーザーのプロセスだけが接続できる。LAN 越しは不可。

正典: `references/16-collab-protocol.md`（プロトコル）、`references/*.schema.json`
（文書 JSON と Op の正確な形）、`references/examples/*.json`（テスト済みの最小例）。
この skill はそれらを使うための導線と落とし穴に絞る。

## Quick Start

### 1. エディタを見つけて認証情報を読む

port file `collab-{pid}.json` を列挙する。無ければ「エディタ未起動、または
設定でローカル API が無効」と判断する。

| OS | 場所 |
| --- | --- |
| Windows | `%TEMP%\hogandoc-{USERNAME}\collab-{pid}.json` |
| Linux | `$XDG_RUNTIME_DIR/hogandoc/collab-{pid}.json`（無ければ `/tmp/hogandoc-{USER}/`） |
| macOS | `$TMPDIR/hogandoc-{USER}/collab-{pid}.json` |

```json
{ "pid": 1234, "port": 7420, "protocol": "collab/v1",
  "docs_url": "http://127.0.0.1:7420/api/v1/docs", "token": "…" }
```

終了時に消えるが、クラッシュ後に残ることが多く、**古い port file は同じポートで
別トークン**を持つ（→ 403 `invalid token`）。必ず `pid` が生きているものを選ぶ
（Node なら `process.kill(pid, 0)`、Python なら `os.kill(pid, 0)`）。

### 2. すべてのリクエストに Bearer トークンを付ける

```sh
BASE=http://127.0.0.1:7420/api/v1
AUTH="Authorization: Bearer $TOKEN"
curl -s $BASE/health                    # これだけ無認証
curl -s -H "$AUTH" $BASE/docs           # 開いているタブ一覧
```

`Host` は `127.0.0.1` / `localhost` のみ許可。`Origin` を付けるなら localhost 系のみ。

### 3. 読む → 変える → 描画で確認する

```sh
DOC=$(curl -s -H "$AUTH" $BASE/docs | jq -r '.docs[0].doc_id')
curl -s -H "$AUTH" $BASE/docs/$DOC | jq '.document.pages[0] | {id, width, height, blocks: (.blocks|length)}'
curl -s -H "$AUTH" -H 'Content-Type: application/json' \
     -d @references/examples/post_ops_request.json $BASE/docs/$DOC/ops
curl -s -H "$AUTH" "$BASE/docs/$DOC/render.png?page=0&dpi=96" -o page0.png
```

`render.png` を必ず見て結果を確認する。送って終わりにしない。

## エンドポイント早見表

すべて `/api/v1` 配下。`{id}` はタブの `doc_id`（`"tab-" + UUIDv7`、タブを閉じるまで不変）。

| 操作 | メソッドとパス | 備考 |
| --- | --- | --- |
| タブ一覧 | `GET /docs` | `doc_id` / `title` / `file_path`（未保存は null）/ `doc_version` |
| 文書取得 | `GET /docs/{id}[?format=json\|xml\|xhg]` | 応答 `{ doc_id, doc_version, document }`。`ETag: "{doc_version}"` |
| 文書全置換 | `PUT /docs/{id}` | ボディ `{ "document": {...} }`。`If-Match: "N"` で楽観ロック（不一致は 409） |
| 差分適用 | `POST /docs/{id}/ops` | ボディは `post_ops_request` schema。1 バッチが原子的。応答 `{ client_seq, server_seq, warnings }`、拒否は 422 |
| 差分取得 | `GET /docs/{id}/ops?since=N` | 他者の変更を追う。古すぎると 410 → 文書を取り直す |
| 入力一覧 | `GET /docs/{id}/inputs` | `input_id` / `input_type` / `value` / `block_id` / `page_id` |
| 入力 1 件 | `GET` / `PUT /docs/{id}/inputs/{input_id}` | PUT は `{ "value": "…" }`。同じ `input_id` は全件更新 |
| 入力一括 | `PATCH /docs/{id}/inputs` | `{ "values": { "amount": "135000", … } }`。1 つでも無ければ 404 で全体拒否 |
| 保存 | `POST /docs/{id}/save` | タブに紐づくファイルへ**無確認で上書き**。未保存タブは 409 |
| 画像取得 | `GET /docs/{id}/media/{media_id}` | `Image.src` が `media:{id}` のときのバイナリ |
| 描画 | `GET /docs/{id}/render.png?page=N&dpi=D` / `render.svg?page=N` / `render.pdf` | `page` は 0 始まり。`dpi` 24〜600 |
| 選択 | `GET` / `PUT /docs/{id}/selection` | `{ "ids": [...] }`。人間に「ここを変えた」と見せるのに使う |
| 参加者 | `GET /docs/{id}/presence` | |
| ログ | `GET /log?tail=N` | `hogandoc.log` の末尾 |
| Schema | `GET /schema` / `GET /schema/{name}` | `document` / `op` / `post_ops_request` / `ws_client_message` / `ws_server_message` / `presence` / `input_info` |

エラーは `{ "error": { "code", "message", "details" } }`。主な `code`:
`not_found` / `version_conflict` / `no_file_path` / `history_gone` /
`invalid_path`（`page_id` が無い）/ `duplicate_id` / `type_mismatch`（JSON が型に合わない）。

## 文書 JSON の要点

```
Document
├─ sections[]            { id, template_name, title }  ページはセクション順に並ぶ
├─ section_page_counts[] sections[i] が持つページ数
├─ pages[]               { id, page_no, paper_size, width, height,
│                          blocks[], lines[], curves[], connectors[], compound_shapes[], groups[] }
├─ templates[]           { name, header, content, footer }  各領域は Page と同じ配列を持つ
├─ compound_shape_templates[]
└─ custom_arrows[]
```

- **ID** は UUIDv7 文字列。`add` では自分で採番し、`object.id` と `value.id` を一致させる。
  `Template` だけは `name` が ID。
- **`page_id` の 3 形式**: `Page.id` / `"document"`（ページ・セクション等の
  ドキュメント直下）/ `"template:{name}/{header|content|footer}"`。ページの
  インデックスは使わない。
- **単位**:
  - 位置・寸法（`x`, `y`, `width`, `height`, 角丸, `text_insets`, `dash_mm`）: **mm**
  - 線幅（`thickness`, `stroke_width`, `border_width`）: **pt**
  - `Run.font_size` / `InputField.font_size`: **論理 px（96dpi）**。pt × 96/72。
    12pt なら 16、16pt なら 21.333。
  - `rotation`: 度、時計回り。
- **色**: `#` 無しの 6 桁 RGB hex（`"1F3A93"`）。`null` は既定色。
- **z 順**: 同じ配列内の並び順が描画順（後ろが手前）。`z` フィールドもあるが、
  順序を変えるときは `reorder` Op で配列順を並べ替える。
- **A4 縦**: `width: 210, height: 297`。座標原点はページ左上、y は下向き。
- **Block の種類** は `content` の外部タグで決まる:
  `{"Text": [Run…]}` / `{"Rect": {…}}` / `{"Circle": {…}}` / `{"Triangle": {…}}` /
  `{"Diamond": {…}}` / `{"Callout": {…}}` / `{"Image": {…}}` / `{"Table": {…}}`。
  図形ブロックの文字は `label`、Text ブロックの文字は runs。
- **入力フィールド**は `content = {"Text": [ { content: {"Input": {...}} } ]}` の
  唯一の run。値だけ変えるなら inputs API を使う（`block_id` を知らなくてよい）。
- 必須フィールドは `document.schema.json` の各 `$defs.*.required` を見る。
  Block は `id, x, y, z, width, height, word_wrap, text_align, vertical_align,
  content, border_visible, corner_radius, rotation` が必須（例を参照）。

## Op の書き方（`references/16-collab-protocol.md` §7）

| kind | 要点 |
| --- | --- |
| `add` | `object` + `page_id`（ページ配下なら必須）+ `value`（全フィールド）。`parent_id` でグループへ。`index` で挿入位置 |
| `update` | `patch` は RFC 7396 merge patch。**配列は丸ごと置換**（runs / waypoints / options）。`null` は既定値に戻す。`content` のタグが同じなら中身にマージ |
| `remove` | グループを消しても子は残る。ページを消すと上の全オブジェクトも消える |
| `move` | 別ページへ。座標は変わらないので必要なら同じバッチに `update` |
| `reorder` | `order` に**その配列の全 ID** を新しい順で。`page_id="document"` + `object_type="page"` でページ順 |
| `replace_document` | 全置換。通常は `PUT /docs/{id}` を使う |

Text ブロックを 1 つ足す最小例（`references/examples/add_text_block.json`）:

```json
{
  "kind": "add",
  "object": { "type": "block", "id": "0199a000-0000-7000-8000-000000000001" },
  "page_id": "<Page.id>",
  "value": {
    "id": "0199a000-0000-7000-8000-000000000001",
    "x": 20, "y": 30, "z": 0, "width": 120, "height": 12,
    "word_wrap": true, "text_align": "Left", "vertical_align": "Top",
    "content": { "Text": [ { "font_size": 16, "bold": false, "italic": false,
                             "underline": false, "strikethrough": false,
                             "content": { "Text": "御見積書" } } ] },
    "border_visible": false, "corner_radius": 0, "rotation": 0
  }
}
```

テキストを差し替える（runs は配列なので全置換になる）:

```json
{ "kind": "update", "object": { "type": "block", "id": "…" },
  "patch": { "content": { "Text": [ { "font_size": 21.333, "bold": true, "italic": false,
             "underline": false, "strikethrough": false, "font_color": "1F3A93",
             "content": { "Text": "御請求書" } } ] } } }
```

他の例: `add_rect_block.json`（四角形）、`add_line.json`（罫線）、
`update_block_position.json`、`post_ops_request.json`（複数 Op を 1 バッチ + reorder）。
これらはエディタ側のテストで型に対して検証されている。

## 作業の進め方

1. `GET /docs` で対象タブを選ぶ。複数あればタイトルとパスを人間に確認する。
2. `GET /docs/{id}` で構造を読む。全体は大きいので `jq` で必要なページ・ブロックに絞る。
3. 既存ブロックを参考に `value` を組む（フォント・色・余白を揃える）。
4. `POST /docs/{id}/ops` で送る。`warnings` と 422 の `message` を読む。
5. `render.png` で確認し、ずれていれば `update` で直す。
6. 人間に見せるときは `PUT /selection` で対象をハイライトする。
7. 保存は**人間が指示したときだけ** `POST /save`。

## 注意・やってはいけないこと

- `PUT /docs/{id}` + `POST /save` は開いているファイルを無確認で上書きできる。
  全置換より `ops` の差分を使い、保存は明示的な指示があるときだけ行う。
- 人間が同時に編集していることがある。`PUT` には `If-Match` を付ける。
  `ops` 適用後の `doc_version` は次の `GET` の `ETag` で分かる。
- エディタ側の Undo はスナップショット復元なので、API の変更も人間の Ctrl+Z
  で巻き戻る。逆も然り。
- 画像は Op で運ばない。`Image.src` に `media:{id}` を置き、バイナリは media
  エンドポイントで扱う（アップロード API は未実装。既存画像の参照のみ）。
- `Checkbox` 入力の値は選択中の `value` を `\u001F`（US, 0x1F）区切りで連結した文字列。JSON では `"a\u001Fc"` と書く。
- `Page.page_no` は送っても無視される（受信側が再計算）。`section_page_counts`
  と `pages` の整合が取れない `PUT` は 422。
- `Run.id` は省略でき、自動採番される。他の `id` は必須。
- 図形ブロック（Rect / Circle …）は `content` 側の `stroke_*` で枠を描く。`border_visible: true`
  だと**さらに四角い枠**が重なるので、Circle などでは `border_visible: false` にする。
- 図形ブロックの文字は `label: { runs, text_align, vertical_align, word_wrap, insets }`。
  複数行は run の `Text` に `
` を入れる。
- `ObjectType` の JSON 値は snake_case（`compound_shape`）、enum 値は多くが
  PascalCase（`"Left"`, `"Solid"`, `"FilledTriangle"`）。迷ったら schema。
- WebSocket（`/docs/{id}/ws`）は他者の変更をリアルタイムに受けたいときだけ。
  最初に `{"type":"hello","protocol":"collab/v1","client_name":"…","auth":{"scheme":"bearer","token":"…"}}`。

## Python 最小スニペット

```python
import glob, json, os, sys, urllib.request

def find_editor():
    for p in sorted(glob.glob(os.path.expandvars(r"%TEMP%\hogandoc-%USERNAME%\collab-*.json"))
                    + glob.glob(os.path.expandvars("$XDG_RUNTIME_DIR/hogandoc/collab-*.json"))
                    + glob.glob(os.path.expandvars("$TMPDIR/hogandoc-$USER/collab-*.json")), reverse=True):
        info = json.load(open(p, encoding="utf-8"))
        try:
            urllib.request.urlopen(f"http://127.0.0.1:{info['port']}/api/v1/health", timeout=1)
            return info
        except Exception:
            continue
    sys.exit("hogandoc-editor is not running (or its local API is disabled)")

info = find_editor()
BASE = f"http://127.0.0.1:{info['port']}/api/v1"
H = {"Authorization": f"Bearer {info['token']}", "Content-Type": "application/json"}

def call(method, path, body=None):
    req = urllib.request.Request(BASE + path, method=method, headers=H,
                                 data=None if body is None else json.dumps(body).encode())
    with urllib.request.urlopen(req) as r:
        return json.load(r)

doc = call("GET", "/docs")["docs"][0]["doc_id"]
page = call("GET", f"/docs/{doc}")["document"]["pages"][0]
op = json.load(open("references/examples/add_text_block.json", encoding="utf-8"))
op["page_id"] = page["id"]
print(call("POST", f"/docs/{doc}/ops", {"client_id": "python", "client_seq": 1, "ops": [op]}))
```

## Reference

- `references/16-collab-protocol.md` — プロトコル正典（§3 REST、§7 Op、§12 入力、§13 エラー、§14 セキュリティ、§19 デバッグ、§20 Schema）
- `references/examples/` — テスト済み Op 例
