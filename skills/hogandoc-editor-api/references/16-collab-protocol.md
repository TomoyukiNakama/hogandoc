| 列挙型 | serde の既定表現（外部タグ付き）。例: `"content": { "Text": [ {run}, … ] }`、`"input_type": { "Text": { "format": "…" } }`。入力フィールドは Text ブロックの唯一の run の `content: { "Input": {...} }` として保持される || 同期対象外 | `view_state`（ズーム・表示ページ）と `current_section`。送っても無視される。`Page.page_no` は wire 上は常に `0` で、受信側が配列順から再採番する |# 同時編集プロトコル仕様 (collab/v1)

> **実装ステータス**: hogandoc-editor 側は実装済み（plan_373〜376: コア `src/collab/`、内蔵ローカルサーバー、プレゼンス、hogandoc-server 接続）。本文書が正であり、hogandoc-server はこの仕様を実装する。

hogandoc のドキュメントを、人間のユーザー・別のユーザー・AI エージェントが**同時に**編集するためのプロトコル。
REST（全体取得・保存・入力フィールド値）と WebSocket（オブジェクト単位の差分＝Op のリアルタイム同期、プレゼンス）から成る。

接続・設定・UI については [docs/17-collab-settings.md](17-collab-settings.md) を参照。

---

## 1. 概要と用語

| 用語 | 意味 |
| --- | --- |
| オーソリティ (authority) | Op に全順序（`server_seq`）を与え、全参加者へ配信する役。**1 ドキュメントにつき 1 つ** |
| クライアント | オーソリティに接続して Op を送受信する参加者。hogandoc-editor、AI エージェント、スクリプト、ブラウザツールなど |
| セッション | 1 クライアントと 1 オーソリティの間の WS 接続。`client_id` で識別 |
| `doc_id` | ドキュメントの識別子（文字列）。内蔵サーバーでは開いているタブの識別子、hogandoc-server ではサーバー上のドキュメント ID |
| Op | ドキュメントへの 1 つの変更（オブジェクトの追加・部分更新・削除・移動・並べ替え） |
| `server_seq` | オーソリティが配信バッチごとに振る単調増加の連番。ドキュメントの全順序 |
| `doc_version` | REST の `ETag` / `If-Match` に使う版番号。`server_seq` と同値 |

### 1.1 2 つのトポロジ

wire 形式（REST / WS メッセージ / Op）は両トポロジで**完全に同一**。違いは「誰がオーソリティか」だけである。

```
【内蔵モード】 同一マシンの AI / スクリプト向け
                                     ┌──────────────────────┐
   AI agent ── HTTP/WS ─┐            │  hogandoc-editor     │
   script   ── HTTP/WS ─┼── 127.0.0.1:7420 ──► │  = オーソリティ       │
   browser  ── HTTP/WS ─┘            │  (Document の実体)    │
                                     └──────────────────────┘

【リモートモード】 ネットワーク越しの他ユーザー向け
   hogandoc-editor (A) ── WS ─┐      ┌──────────────────────┐
   hogandoc-editor (B) ── WS ─┼────► │  hogandoc-server     │
   AI agent            ── WS ─┘      │  = オーソリティ       │
                                     └──────────────────────┘
```

内蔵モードで hogandoc-editor 自身が hogandoc-server に接続している場合、editor は上流に対してはクライアント、下流（ローカル AI）に対してはリレーとして振る舞う。このとき `server_seq` は上流のものをそのまま転送する。

---

## 2. バージョニング

| 項目 | 規則 |
| --- | --- |
| プロトコル名 | `"collab/v1"`。`hello` / `welcome` で交換する |
| 未知フィールド | 受信側は無視する（前方互換） |
| 未知の `op.kind` | `reject` (`unsupported_op`) を返し、セッションは継続する |
| 未知のメッセージ `type` | `error` (`unsupported_message`) を返し、セッションは継続する |
| メジャー不一致 | `hello_reject` を返して切断する |
| REST のパス | `/api/v1/...`。破壊的変更時は `/api/v2/` を追加し `v1` は維持する |

---

## 3. REST エンドポイント

すべて `Content-Type: application/json`（`format` で他形式を指定した場合を除く）。
内蔵サーバーと hogandoc-server で共通。「内蔵のみ」と記したものは hogandoc-server では `404` を返してよい。

| メソッド | パス | 説明 |
| --- | --- | --- |
| `GET` | `/api/v1/health` | 稼働確認。`{"protocol":"collab/v1","server":"hogandoc-editor/0.3.1"}` |
| `GET` | `/api/v1/docs` | ドキュメント一覧 |
| `GET` | `/api/v1/docs/{doc_id}` | ドキュメント全体の取得 |
| `PUT` | `/api/v1/docs/{doc_id}` | ドキュメント全体の置換 |
| `POST` | `/api/v1/docs/{doc_id}/save` | ファイルへ保存（**内蔵のみ**） |
| `GET` | `/api/v1/docs/{doc_id}/ops?since=N` | `server_seq > N` の Op を取得 |
| `POST` | `/api/v1/docs/{doc_id}/ops` | Op の投入（WS を使えないクライアント向け） |
| `GET` | `/api/v1/docs/{doc_id}/inputs` | 入力フィールド一覧 |
| `GET` | `/api/v1/docs/{doc_id}/inputs/{input_id}` | 入力フィールド値の取得 |
| `PUT` | `/api/v1/docs/{doc_id}/inputs/{input_id}` | 入力フィールド値の設定 |
| `PATCH` | `/api/v1/docs/{doc_id}/inputs` | 入力フィールド値の一括設定 |
| `GET` | `/api/v1/docs/{doc_id}/presence` | 現在の参加者一覧 |
| `GET` | `/api/v1/docs/{doc_id}/media/{media_id}` | 画像バイナリの取得 |
| `GET` | `/api/v1/schema` | 文書・Op・WS メッセージの JSON Schema 一括（§20、**内蔵のみ**） |
| `GET` | `/api/v1/schema/{name}` | JSON Schema 単体（§20、**内蔵のみ**） |

### `GET /api/v1/docs`

```json
{
  "docs": [
    {
      "doc_id": "tab-0198a0f1-7c3e-7b2a-9f10-3b2c1d0e4f55",
      "title": "見積書.xhg",
      "file_path": "D:/work/見積書.xhg",
      "doc_version": 128,
      "peers": 2
    }
  ]
}
```

内蔵サーバーの `doc_id` は `"tab-" + ドキュメント生成時の UUIDv7`。タブを閉じるまで不変。`file_path` は未保存なら `null`。

### `GET /api/v1/docs/{doc_id}`

| クエリ | 値 | 説明 |
| --- | --- | --- |
| `format` | `json`（既定） / `xml` / `xhg` | `json` は §4 の JSON 表現、`xml` は [docs/09-xml-format.md](09-xml-format.md) の XML 文字列、`xhg` は zip パッケージ（`application/zip`） |

応答ヘッダ `ETag: "128"`（= `doc_version`）。

```json
{
  "doc_id": "tab-0198a0f1-…",
  "doc_version": 128,
  "document": { "...": "§4 参照" }
}
```

### `PUT /api/v1/docs/{doc_id}`

ボディは `GET` と同じ `{ "document": {...} }`（`format=xml` の場合は XML 文字列をそのまま）。
`If-Match: "128"` を付けると、現在の `doc_version` と一致しない場合に `409 version_conflict` を返す。省略時は無条件に置換する。
内部的には `replace_document` Op として全参加者に配信される。応答は `{ "doc_version": 129 }`。

### `POST /api/v1/docs/{doc_id}/save` （内蔵のみ）

現在の内容をタブに紐づくファイルへ保存する。未保存タブは `409 no_file_path`。応答 `{ "file_path": "…" }`。

### `GET /api/v1/docs/{doc_id}/ops?since=N`

```json
{
  "server_seq": 131,
  "ops": [
    { "server_seq": 129, "client_id": "…", "client_seq": 7, "ops": [ { "kind": "update", "...": "…" } ] },
    { "server_seq": 130, "client_id": "…", "client_seq": 8, "ops": [ "…" ] }
  ]
}
```

`N` がリングバッファ（§10）の保持範囲より古い場合は `410 history_gone`。クライアントは `GET /docs/{doc_id}` で全体を取り直す。

### `POST /api/v1/docs/{doc_id}/ops`

```json
{ "client_id": "optional-任意の文字列", "client_seq": 1, "ops": [ { "kind": "update", "...": "…" } ] }
```

`client_id` を省略するとリクエストごとに匿名 ID が振られる（冪等性なし）。応答は WS の `ack` と同形 `{ "client_seq": 1, "server_seq": 132 }`。拒否は `422` で `reject` と同形。

### 入力フィールド API

§12 を参照。

### `GET /api/v1/docs/{doc_id}/media/{media_id}`

画像ブロックの `src` が `media:{media_id}` のとき、そのバイナリを返す。`Content-Type` は保存時の MIME。
画像バイナリは Op では運ばない（§16）。

---

## 4. 文書 JSON 表現

`document` は Rust の `Document` 構造体を `serde_json` で直列化したものを正とする。
XML 形式（[docs/09-xml-format.md](09-xml-format.md)）と同じ情報量を持ち、単位・座標系も同じ。

| 項目 | 規則 |
| --- | --- |
| スキーマ | `schemars` で型定義から生成した [docs/schema/document.schema.json](schema/document.schema.json) が正確な形（§20、plan_438）。`GET /api/v1/schema/document` でも取れる |
| 座標・サイズ | mm。`Block.x / y / width / height`、`Line.x1…`、`Connector.source_x…`、`Connector.waypoints` |
| 線の太さ | pt |
| 回転 | 度、時計回り正 |
| `Run.font_size` | **アプリ論理 px (96dpi)**。pt ではない（plan_369）。12 = 9pt |
| 色 | `"RRGGBB"`（`#` なし、大文字） |
| ID | 全オブジェクトが UUIDv7 文字列。`Block.id` / `Line.id` / `Page.id` / `Run.id` など |
| 同期対象外 | `view_state`（ズーム・表示ページ）と `current_section`。送っても無視される |
| 列挙型 | serde の既定表現（外部タグ付き）。例: `"content": { "Text": [ {run}, … ] }`、`"input_type": { "Text": { "format": "…" } }` |

構造の概略（抜粋）:

```json
{
  "templates": [ { "name": "default", "header": {}, "content": {}, "footer": {} } ],
  "sections": [ { "id": "…", "template_name": "default", "title": "…" } ],
  "pages": [
    {
      "id": "0198a0f2-…",
      "page_no": 0,
      "paper_size": "A4Portrait",
      "width": 210.0,
      "height": 297.0,
      "blocks": [
        {
          "id": "0198a0f3-…",
          "x": 20.0, "y": 30.0, "width": 80.0, "height": 12.0,
          "z": 0,
          "rotation": 0.0,
          "content": { "Text": [ { "id": "…", "content": { "Text": "見積金額" }, "font_size": 16.0, "bold": true } ] }
        },
        {
          "id": "0198a0f4-…",
          "x": 110.0, "y": 30.0, "width": 60.0, "height": 10.0,
          "content": { "Text": [ { "id": "…", "content": { "Input": { "input_id": "amount", "input_type": { "Number": { "unit": "円" } }, "value": "120000" } } } ] }
        }
      ],
      "lines": [], "curves": [], "connectors": [], "compound_shapes": [], "groups": []
    }
  ],
  "section_page_counts": [ 1 ],
  "compound_shape_templates": [],
  "custom_arrows": []
}
```

省略されたフィールドは Rust 側の `#[serde(default)]` により既定値で補完される。完全なフィールド一覧はスキーマを参照。

---

## 5. WebSocket セッション

| 項目 | 値 |
| --- | --- |
| URL | `ws://{host}/api/v1/docs/{doc_id}/ws` （hogandoc-server は `wss://`） |
| サブプロトコル | なし（テキストフレーム、JSON 1 メッセージ/フレーム） |
| 最初のメッセージ | クライアントが `hello` を送る。10 秒以内に来なければ切断 |
| Keep-alive | クライアントは 30 秒ごとに `ping`。オーソリティは `pong`。90 秒無通信で切断 |

### ハンドシェイク

```
C → S  hello   { protocol, client_name, color, last_server_seq? }
S → C  welcome { client_id, server_seq, doc_version, snapshot?, ops?, presence[] }
```

| 条件 | `welcome` の内容 |
| --- | --- |
| 初回接続（`last_server_seq` なし） | `snapshot` = 文書全体（§4）。`ops` なし |
| 再接続、`last_server_seq` がリングバッファ内 | `snapshot` なし。`ops` = `last_server_seq` より後の全バッチ |
| 再接続、範囲外 | 初回と同じ（`snapshot` あり） |

---

## 6. メッセージ種別

すべて `{"type": "...", ...}` の JSON オブジェクト。

### 6.1 クライアント → オーソリティ

#### `hello`

| フィールド | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `protocol` | string | ○ | `"collab/v1"` |
| `client_name` | string | ○ | 表示名（プレゼンスに使う） |
| `color` | string | — | `"#RRGGBB"`。省略時はオーソリティが `client_id` から決める |
| `last_server_seq` | u64 | — | 再接続時、最後に受信した `server_seq` |
| `auth` | object | — | 将来拡張（§15）。第1段階では無視 |

```json
{ "type": "hello", "protocol": "collab/v1", "client_name": "Claude", "color": "#7C4DFF" }
```

#### `ops`

| フィールド | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `client_seq` | u64 | ○ | このクライアントでの送信バッチ連番（1 始まり、単調増加） |
| `ops` | Op[] | ○ | 1 件以上。**1 バッチはアトミックに適用**される（全件成功か全件拒否） |

```json
{
  "type": "ops",
  "client_seq": 7,
  "ops": [
    { "kind": "update", "object": { "type": "block", "id": "0198a0f3-…" }, "patch": { "x": 25.0, "y": 31.5 } }
  ]
}
```

#### `presence`

§11 を参照。

#### `ping`

```json
{ "type": "ping" }
```

### 6.2 オーソリティ → クライアント

#### `welcome`

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `client_id` | string | このセッションの ID（UUIDv7） |
| `server_seq` | u64 | 現在の最新 `server_seq` |
| `doc_version` | u64 | = `server_seq` |
| `snapshot` | Document | 文書全体（§5 の条件で省略） |
| `ops` | Broadcast[] | 差分（§5 の条件で省略）。各要素は下記 `ops` メッセージと同形 |
| `presence` | Presence[] | 現在の他参加者 |

#### `hello_reject`

```json
{ "type": "hello_reject", "code": "unsupported_protocol", "message": "expected collab/v1" }
```

#### `ops` （ブロードキャスト）

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `server_seq` | u64 | このバッチの連番 |
| `client_id` | string | 送信元 |
| `client_seq` | u64 | 送信元でのバッチ連番 |
| `ops` | Op[] | 適用済みの Op（オーソリティが正規化した後の形） |

**送信元自身にも配信される**（§9）。

#### `ack`

```json
{ "type": "ack", "client_seq": 7, "server_seq": 129, "warnings": [ { "op_index": 0, "code": "stale_target", "message": "block … was already removed" } ] }
```

`warnings` は適用はされたが注意が必要なもの（例: 削除済みオブジェクトへの `update` を無視した）。省略可。

#### `reject`

```json
{ "type": "reject", "client_seq": 7, "op_index": 1, "code": "duplicate_id", "message": "block 0198… already exists" }
```

バッチ全体が破棄される。`op_index` は最初に失敗した Op の位置。

#### `presence` / `peer_joined` / `peer_left`

§11 を参照。

#### `snapshot`

```json
{ "type": "snapshot", "server_seq": 140, "document": { "…": "…" } }
```

オーソリティが強制再同期を指示する。クライアントは `pending` を破棄し、文書を置き換える。`reject` の後（§9）や、オーソリティ側で `replace_document` が起きた後に送られる。

#### `error`

```json
{ "type": "error", "code": "too_large", "message": "frame exceeds 32MB" }
```

セッションは継続する（致命的なら続けて切断）。

#### `pong`

```json
{ "type": "pong" }
```

---

## 7. Op スキーマ

### 共通

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `kind` | string | `add` / `update` / `remove` / `move` / `reorder` / `replace_document` |
| `object` | `{ "type": ObjectType, "id": string }` | 対象（`reorder` / `replace_document` 以外で必須） |

`ObjectType`:

| 値 | 所属 | 備考 |
| --- | --- | --- |
| `block` | page / template region | テキスト・画像・入力・図形ブロック |
| `line` | page / template region | |
| `curve` | page / template region | |
| `connector` | page / template region | |
| `compound_shape` | page / template region | 複合図形インスタンス |
| `group` | page | |
| `page` | document | |
| `section` | document | |
| `template` | document | ページテンプレート。`id` はテンプレート名 |
| `compound_shape_template` | document | |
| `custom_arrow` | document | |

ページ配下オブジェクトの所属は `page_id`（`Page.id`）で指定する。**ページのインデックスは使わない**（他者のページ挿入で変わるため）。テンプレート領域内のオブジェクトは `"page_id": "template:{name}/{header|content|footer}"` とする。

### `add`

| フィールド | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `object` | | ○ | `id` は**クライアントが採番**する（UUIDv7 推奨）。`value.id` と一致すること |
| `page_id` | string | page 配下なら○ | 所属ページ |
| `parent_id` | string | — | グループに入れる場合の `group` ID |
| `value` | object | ○ | オブジェクト全体（§4 の JSON） |
| `index` | usize | — | 配列内の挿入位置。省略時は末尾 |

```json
{
  "kind": "add",
  "object": { "type": "line", "id": "0198a100-…" },
  "page_id": "0198a0f2-…",
  "value": { "id": "0198a100-…", "x1": 10, "y1": 50, "x2": 190, "y2": 50, "thickness": 0.5, "color": "000000" }
}
```

### `update`

| フィールド | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `object` | | ○ | |
| `patch` | object | ○ | [RFC 7396 JSON Merge Patch](https://www.rfc-editor.org/rfc/rfc7396)。オブジェクトのトップレベルからの部分更新 |

規則:

- `patch` のキーは再帰的にマージされる。`null` はフィールドを既定値に戻す（削除ではない。Rust 側の `Option` は `None`、それ以外は `#[serde(default)]` の値）
- **配列は全体置換**（`runs`、`waypoints`、`options`、`children` など）。要素単位の差し替えはできない
- 外部タグ付き列挙型（`content`、`input_type`）は、タグが同じならその中身にマージ、タグが違えば全体置換
- 適用後に構造体へ復元できない（型不一致）場合は `reject` (`type_mismatch`)

```json
{ "kind": "update", "object": { "type": "block", "id": "0198a0f4-…" }, "patch": { "content": { "Input": { "value": "135000" } } } }
```

### `remove`

```json
{ "kind": "remove", "object": { "type": "block", "id": "0198a0f3-…" } }
```

グループを `remove` しても子は残る（グループ解除と同じ）。ページを `remove` するとページ上の全オブジェクトも消える。

### `move`

ページ間移動。同一ページ内の z 順変更は `reorder`。

| フィールド | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `object` | | ○ | |
| `to_page_id` | string | ○ | 移動先 |
| `index` | usize | — | 移動先配列内の位置。省略時は末尾 |

座標は**変更しない**（ページ内座標のまま）。座標も変えたい場合は同じバッチに `update` を並べる。

### `reorder`

| フィールド | 型 | 必須 | 説明 |
| --- | --- | --- | --- |
| `page_id` | string | ○ | 対象ページ（または `"template:…"`、`"document"`） |
| `object_type` | ObjectType | ○ | どの配列を並べ替えるか（`block` / `line` / … / `page` / `section`） |
| `order` | string[] | ○ | **全要素**の ID を新しい順に並べたもの |

```json
{ "kind": "reorder", "page_id": "0198a0f2-…", "object_type": "block", "order": [ "0198a0f4-…", "0198a0f3-…" ] }
```

`order` に現在の要素と過不足がある場合: 不足分は末尾に現在の相対順で付け足し、余分は無視する（`ack` に `warning`）。
`page_id = "document"`, `object_type = "page"` でページ順を、`object_type = "section"` でセクション順を変える。

### `replace_document`

```json
{ "kind": "replace_document", "document": { "…": "…" } }
```

全体置換。REST の `PUT` が内部でこれを発行する。受信クライアントは `pending` を破棄する。

---

## 8. 順序付けと競合解決

1. オーソリティは `ops` バッチを**受信順**に処理し、成功したバッチに `server_seq` を振って全員へ配信する。配信順 = 適用順。
2. 同一 `(object_id, フィールドパス)` への `update` は **後着（`server_seq` が大きい方）が勝つ**（Last-Writer-Wins）。異なるフィールドへの同時更新は両方残る。A が位置、B が塗り色を同時に変えても、両方反映される。
3. 既に `remove` されたオブジェクトへの `update` / `move` は**無視**し、`ack` に `stale_target` の warning を付ける（reject しない。他者の削除で自分の編集が失敗するのを避けるため）。
4. `add` で既存の ID と衝突したら `reject` (`duplicate_id`)。クライアントは新しい ID で再送する。
5. `reorder` は全列を送るので、2 人が同時に並べ替えても後着の列で収束する。
6. テキスト Run は `update` で `content.Text` 配列全体が置換される。2 人が同じブロックの文章を同時に編集すると後着が勝つ（文字単位のマージはしない、§16）。
7. バッチ内の Op は上から順に適用され、途中で失敗したらバッチ全体を破棄する（アトミック）。

---

## 9. クライアントの適用手順

```
ローカル編集発生
  ├─ 即座に自分の Document に反映（楽観適用）
  ├─ Op を生成し client_seq を振って pending に積む
  └─ 接続中なら送信

受信: ops (client_id == 自分)
  └─ 適用しない。pending から該当 client_seq を除去（= ack 相当）

受信: ops (client_id != 自分)
  └─ そのまま適用。pending と同じフィールドを触っていても適用する
     （自分の pending はこの後オーソリティで処理され、さらに後の server_seq で
       全員に届くので、最終的に全員が同じ値に収束する）

受信: ack
  └─ pending から除去。warnings はログ

受信: reject
  └─ 楽観適用した変更を局所的に巻き戻す手段がないため、
     pending を破棄し snapshot を待つ（オーソリティは reject 直後に snapshot を送る）

受信: snapshot / replace_document
  └─ pending を破棄し文書を置換
```

hogandoc-editor の実装では、ローカル編集の Op 化は「前回同期済みスナップショットとの diff」で行う（[docs/17-collab-settings.md](17-collab-settings.md) §1.2）。

---

## 10. 再送と再接続

| 項目 | 規則 |
| --- | --- |
| `client_seq` | セッションをまたいで単調増加（再接続しても 1 に戻さない） |
| 切断中の編集 | `pending` に積み続ける。再接続の `welcome` を受けて `ops` 差分を適用した**後**に、`pending` を古い順に再送する |
| 冪等性 | オーソリティは `client_id` ごとに最後に処理した `client_seq` を覚え、それ以下の `client_seq` は**処理せず `ack` だけ返す** |
| `client_id` の継続 | 再接続時の `hello` に `client_id` を含めれば同じ ID を継続できる（含めなければ新規）。オーソリティは切断から 10 分間 `client_id` の `client_seq` 記録を保持する |
| リングバッファ | オーソリティは直近 **1000 バッチ**の `ops` ブロードキャストを保持する。`ops?since=` と再接続差分に使う |
| バックオフ | クライアントの再接続は 1s → 2s → 4s → … 最大 30s |

---

## 11. プレゼンス

誰がどのページのどのオブジェクトを選択・編集中かを共有する。順序付け不要、最新値のみ有効。

### `presence` （C → S、S → C 共通）

| フィールド | 型 | 説明 |
| --- | --- | --- |
| `client_id` | string | S → C のとき付与。C → S では省略 |
| `name` | string | 表示名 |
| `color` | string | `"#RRGGBB"` |
| `page_id` | string? | 現在表示中のページ |
| `selection` | string[] | 選択中オブジェクトの ID |
| `editing_block` | string? | テキスト編集中のブロック ID |
| `cursor` | `{ "page_id", "x", "y" }?` | マウス位置（mm）。省略可 |

```json
{ "type": "presence", "page_id": "0198a0f2-…", "selection": [ "0198a0f3-…" ], "editing_block": null }
```

| 規則 | 内容 |
| --- | --- |
| スロットル | クライアントは 100ms に 1 回まで送る。最後の状態だけ送ればよい |
| 配信 | オーソリティは送信元以外の全員へ転送する。`name` / `color` は `hello` の値で補完する |
| `peer_joined` | `{ "type": "peer_joined", "client_id", "name", "color" }` |
| `peer_left` | `{ "type": "peer_left", "client_id" }`。切断検知時 |
| REST | `GET /presence` は `{ "peers": [ Presence… ] }` |

---

## 12. 入力フィールド API

帳票連携向けの軽量 API。`InputField.input_id` をキーにする。WS の `update` と等価だが、`block_id` を知らなくてよい。

入力フィールドは `Block.content = { "Text": [ run ] }` の唯一の run の `content = { "Input": {...} }` として保持される。merge patch は配列要素を狙えないため、WS で同じことをするには値を差し替えた runs 配列全体を `{ "content": { "Text": [ ... ] } }` で送る。

### 値の形式

| `input_type` | `value` の形式 | 例 |
| --- | --- | --- |
| `Text` | 任意文字列 | `"山田 太郎"` |
| `Number` / `Decimal` | 数値の文字列表現。桁数制約は `input_type` の `integer_digits` / `decimal_digits` | `"120000"`, `"3.14"` |
| `Date` | `YYYY-MM-DD` | `"2026-08-22"` |
| `Time` | `HH:MM` または `HH:MM:SS` | `"09:30"` |
| `DateTime` | `YYYY-MM-DDTHH:MM` | `"2026-08-22T09:30"` |
| `Select` / `Radio` | 選択肢の `value` | `"approved"` |
| `Checkbox` | 選択中の `value` を **`\u001F`（US, 0x1F）区切り**で連結 | `"a\u001Fc"` |

REST / WS とも `value` は常に文字列。`Checkbox` は JSON 上は `"a\u001Fc"` と書く（実装都合の区切り文字を露出している。将来 `values: []` 形式を追加する可能性がある）。

### `GET /api/v1/docs/{doc_id}/inputs`

```json
{
  "inputs": [
    { "input_id": "amount", "input_type": "Number", "value": "120000", "block_id": "0198a0f4-…", "page_id": "0198a0f2-…", "nullable": false }
  ]
}
```

`input_type` はタグ名のみ。

### `GET /api/v1/docs/{doc_id}/inputs/{input_id}`

```json
{ "input_id": "amount", "value": "120000", "matches": 1 }
```

同じ `input_id` が複数ある場合は最初の 1 件（ページ順・z 順）の値と `matches` 件数を返す。

### `PUT /api/v1/docs/{doc_id}/inputs/{input_id}`

```json
{ "value": "135000" }
```

同じ `input_id` を持つ**全件**を更新する。存在しなければ `404`。応答 `{ "updated": 1, "doc_version": 133 }`。

### `PATCH /api/v1/docs/{doc_id}/inputs`

```json
{ "values": { "amount": "135000", "customer": "株式会社ほがん" } }
```

1 バッチの Op として適用（アトミック）。存在しない `input_id` が含まれていたら `404` で全体を拒否する。応答 `{ "updated": 2, "missing": [], "doc_version": 134 }`。

### 値の検証

`min_value` / `max_value` / 桁数の制約は**検証しない**（エディタの入力モードと同じく、表示時に `threshold_action` で扱う）。型として解釈不能な値（`Date` に `"abc"`）も保存はされる。

---

## 13. エラー形式

### REST

```json
{ "error": { "code": "not_found", "message": "doc tab-… not found", "details": null } }
```

| HTTP | `code` | 意味 |
| --- | --- | --- |
| 400 | `bad_request` | JSON として解釈不能、必須フィールド欠落 |
| 404 | `not_found` | `doc_id` / `input_id` / `media_id` が存在しない |
| 409 | `version_conflict` | `If-Match` 不一致 |
| 409 | `no_file_path` | 未保存タブへの `save` |
| 410 | `history_gone` | `since` がリングバッファ範囲外 |
| 413 | `too_large` | ボディが 32MB 超 |
| 415 | `unsupported_format` | `format` が不正 |
| 422 | （`reject` と同形） | Op の適用失敗 |
| 503 | `not_ready` | 起動直後などでドキュメントが未準備 |

### WS （`reject` / `error` の `code`）

| `code` | 意味 |
| --- | --- |
| `unsupported_protocol` | `hello.protocol` 不一致（`hello_reject`） |
| `unsupported_op` | 未知の `kind` |
| `unsupported_message` | 未知の `type` |
| `not_found` | `object` が存在しない（`add` 以外で、かつ削除済みではなく最初から無い） |
| `duplicate_id` | `add` の ID 衝突、または `hello.client_id` が**接続中の別セッション**に使用済み（`hello_reject`。plan_413 H8） |
| `already_joined` | 同じ接続で 2 回目の `hello`（`hello_reject`。plan_413 M8） |
| `unauthorized` | `hello.auth` が無い / トークンが不正（`hello_reject`。plan_413 I1） |
| `invalid_path` | `page_id` / `to_page_id` / `parent_id` が存在しない、または `object_type` とページの組が不正 |
| `type_mismatch` | `patch` / `value` を構造体に復元できない |
| `too_large` | フレームが 32MB 超 |
| `internal` | オーソリティ内部エラー |

---

## 14. セキュリティ

内蔵サーバーは**到達範囲を物理的に絞る**うえで、**アクセストークンを必須**にする
（plan_413 I1）。到達範囲だけに頼ると、信頼境界が「このエディタ」ではなく
**「同一マシンの全プロセス」と「任意の localhost ポートで動く任意のページ」**に
なってしまうため（`PUT /docs/{id}` + `POST /docs/{id}/save` で開いているファイルを
無確認で上書きできた）。

| 項目 | 規則 |
| --- | --- |
| バインド先 | 内蔵サーバーは `127.0.0.1` **固定**。`0.0.0.0` は設定で選べない |
| ポート | 既定 `7420`。`0` で OS 自動割当 |
| **認証** | REST は `Authorization: Bearer {token}`、WS は `hello.auth`（§15）。**`GET /api/v1/health` のみ無認証**（返すのはプロトコル名とバージョンだけ）。トークンはプロセス起動ごとにランダム生成し、下のポート公開ファイルに書く |
| ポートの公開 | 実際にバインドしたポートとトークンを `{実行時ディレクトリ}/collab-{pid}.json` に `{ "pid", "port", "protocol": "collab/v1", "docs_url": "http://127.0.0.1:{port}/api/v1/docs", "token": "…" }` として書き出す。終了時に削除。スクリプト / AI はこのファイルを列挙してエディタを発見し、同じファイルからトークンを読む |
| 実行時ディレクトリ | `$XDG_RUNTIME_DIR/hogandoc`（無ければ `{tmp}/hogandoc-{user}`）。**0700 で作成し、既存が symlink または他ユーザー所有なら使わない**。共有 `/tmp` に予測可能な名前で置くと、他ユーザーが symlink を仕掛けて書き込みを乗っ取れる（plan_413 M7） |
| `Host` | loopback（`localhost` / `127.0.0.1` / `::1`）以外は `403`。**DNS rebinding 対策**。`Origin` はブラウザが same-origin GET に付けないため、`Origin` 検査だけでは読み取りを防げない（plan_413 M3） |
| `Origin` | WS / REST に `Origin` ヘッダがある場合、`http://localhost[:port]` / `http://127.0.0.1[:port]` 以外は `403`。ブラウザからの CSRF 対策。ヘッダなし（curl 等）は許可 |
| CORS | `Access-Control-Allow-Origin` は上記 2 オリジンのみ |
| サイズ上限 | HTTP ボディ・WS フレームとも 32MB |
| 接続数上限 | 1 ドキュメントあたり WS 32 本。超過は `503` |
| 送信キュー | 1 接続あたり 64 メッセージ。溢れたら**その接続を切る**（再接続時に snapshot で取り直す。plan_413 M8） |
| プレゼンス | `client_name` 256 バイト、`selection` 4096 件で切り詰め。非有限の `cursor` は捨てる（plan_413 M8） |
| 再送リング | 1000 件かつ合計 256MB。超過分は古い順に捨て、`ops_since` は `None`（= snapshot 再同期）を返す（plan_413 M8） |
| `hello` | 1 接続 1 回。接続中の `client_id` は名乗れない（上の `already_joined` / `duplicate_id`） |
| ログ | 接続・切断・`reject` を `hogandoc.log` に記録。Op の中身は記録しない |
| hogandoc-server | TLS (`wss://`) 必須。認証はサーバー側の責務（§15） |

---

## 15. 認証

| 箇所 | 形式 | 状態 |
| --- | --- | --- |
| `hello.auth` | `{ "scheme": "bearer", "token": "…" }` | **内蔵サーバーで実装済み**（plan_413 I1） |
| REST | `Authorization: Bearer {token}` | **内蔵サーバーで実装済み** |
| `hello_reject.code` | `unauthorized` | 実装済み |
| HTTP | `401 unauthorized` / `403 forbidden` | 実装済み |
| 設定 | `web_api_endpoints[].token`（[docs/17-collab-settings.md](17-collab-settings.md)） | hogandoc-server 接続向け。**未配線** |

**WS でトークンをヘッダではなく `hello.auth` で送る理由**: ブラウザの
`WebSocket` コンストラクタは upgrade 要求に任意ヘッダを付けられない。
プロトコルが最初から `hello.auth` を予約していたのはこのため。

**hogandoc-server 接続側は未配線**。`Session::hello()` は `auth: None` 固定で、
`web_api_endpoints[].token` は設定スキーマにあるだけで読まれていない。
権限モデル（閲覧のみ / 編集可）は `welcome` に `"role": "editor" | "viewer"` を
追加して表す予定。`viewer` からの `ops` は `reject` (`forbidden`)。

権限モデル（閲覧のみ / 編集可）は `welcome` に `"role": "editor" | "viewer"` を追加して表す予定。`viewer` からの `ops` は `reject` (`forbidden`)。

---

## 16. 制限事項

| 制限 | 内容 | 将来 |
| --- | --- | --- |
| テキストの文字単位マージ | なし。同じブロックの同時編集は後着勝ち | Run 単位の差分 Op |
| `reject` 後のロールバック | 局所的な巻き戻しはせず、`snapshot` で再同期 | 逆 Op の保持 |
| 画像バイナリ | Op では運ばない。`add` / `update` で `src` に `media:{id}` を指定し、バイナリは REST `media` で別途やりとり | 画像アップロード API |
| Undo / Redo | hogandoc-editor の Undo は**ローカルのスナップショット**へ戻す。その差分も Op として配信されるため、**他者の変更を巻き戻しうる** | 他者変更保護フィルタ |
| テンプレート変更 | `template` / `compound_shape_template` の `update` は影響ページ全体の再描画になる | |
| `view_state` | 同期しない（各自のズーム・表示位置は独立） | |
| ページ番号 | `page_no` は各クライアントが `pages` 配列から再計算する。Op で送っても無視 | |

---

## 17. 関連ドキュメント

- [docs/17-collab-settings.md](17-collab-settings.md) — 接続・設定・UI
- [docs/09-xml-format.md](09-xml-format.md) — XML 形式（`format=xml` の内容）
- [docs/01-data-model.md](01-data-model.md) — データモデル
- [docs/03-input-fields.md](03-input-fields.md) — 入力フィールド
- [docs/12-settings.md](12-settings.md) — 設定項目

---

## 18. 保守: 図形・プロパティを追加したときの API への追従

| 変更 | API 側の対応 |
| --- | --- |
| 既存の図形にフィールドを追加 | **不要**。`Document` の serde 派生 JSON をそのまま運ぶため、`add.value` / `update.patch` / diff / apply に自動で乗る。`#[serde(default)]` を付けて、古いクライアントが送る JSON（新フィールドなし）も受け付けられるようにする |
| （上記いずれでも）JSON Schema の再生成 | `HOGANDOC_UPDATE_SCHEMA=1 cargo test --lib collab::schema` で `docs/schema/*.schema.json` を書き直してコミットする。`collab::schema::tests::schema_files_are_up_to_date` が乖離を検出する（§20） |
| オブジェクト種別を追加（`Page` / `Document` / `TemplateRegion` に新しい配列） | §7 の `ObjectType` 表、`src/collab/op.rs`、`src/collab/presence_geometry.rs`（外接矩形）を更新。`collab::op::coverage_tests` が未対応を検出する |
| `InputType` のバリアントを追加 | §12 の値形式表と `src/collab/inputs.rs` の `type_name` |
| 同期対象外にしたいフィールドを追加 | §4 の「同期対象外」と `src/collab/json.rs` の `EXCLUDED_*` |

プロトコルのバージョン（`collab/v1`）は、フィールド追加では上げない（§2: 未知フィールドは無視）。`kind` やメッセージ `type` の意味が変わるときだけ上げる。

---

## 19. デバッグ用エンドポイント（内蔵のみ）

AI・スクリプトが「API で図形を作る → 描画結果を見る → 直す」を自力で回すための補助。hogandoc-server は実装しなくてよい（`404`）。

| メソッド | パス | 説明 |
| --- | --- | --- |
| `GET` | `/api/v1/docs/{doc_id}/render.png?page=N&dpi=D` | ページ N（0 始まり）を PNG で描画。`dpi` 既定 96、24〜600。SVG 書き出し経路（resvg）なので見た目は SVG / PDF と一致 |
| `GET` | `/api/v1/docs/{doc_id}/render.svg?page=N` | ページ N の SVG |
| `GET` | `/api/v1/docs/{doc_id}/render.pdf` | 文書全体の PDF |
| `GET` | `/api/v1/docs/{doc_id}/selection` | キャンバスの選択状態 |
| `PUT` | `/api/v1/docs/{doc_id}/selection` | 選択を置き換える。`{ "ids": [...] }`。空で全解除。種別は文書から判定。見つからない ID は `missing` に入る |
| `GET` | `/api/v1/log?tail=N` | `hogandoc.log` の末尾 N 行（既定 200、最大 5000）。`text/plain` |

### `GET /api/v1/docs/{doc_id}/selection`

```json
{
  "page_index": 0,
  "blocks": [ "0198a0f3-…" ],
  "lines": [], "curves": [], "connectors": [], "compound_shapes": [],
  "editing_block": null
}
```

### `PUT /api/v1/docs/{doc_id}/selection`

```json
{ "ids": [ "0198a0f3-…", "ghost" ] }
```

応答 `{ "selection": { ... }, "missing": [ "ghost" ] }`。テキスト編集中なら編集を終了してから選択する。選択はプレゼンスとしても配信される。

### セキュリティ

描画・ログは文書内容そのものを返すため、§14 の `127.0.0.1` バインド・
`Origin` / `Host` 検査・**トークン認証**が前提。

`render.*` と `media` の応答には次を付ける（plan_413 M4）:

```
Content-Disposition: attachment
Content-Security-Policy: default-src 'none'; sandbox
X-Content-Type-Options: nosniff
```

`render.svg` は `image/svg+xml` なので、ブラウザで直接開かれると
**アクティブな文書として描画される**。トップレベル遷移には `Origin` が
付かないため、ヘッダ側でも無害化しておく。

---

## 20. JSON Schema（内蔵のみ、plan_438）

LLM / スクリプトに「文書 JSON と Op の正確な形」を渡すための生成物。
`src/collab/schema.rs` が Rust の型定義から `schemars` で生成する（draft 2020-12）。
図形にフィールドを足すと自動で追従する。

| 名前 | 対象 | 用途 |
| --- | --- | --- |
| `document` | `Document` | `GET /docs/{id}` の `document`、`PUT` のボディ、`replace_document`。図形型は `$defs` にある |
| `op` | `Op` | §7 |
| `post_ops_request` | `POST /docs/{id}/ops` のボディ | §3 |
| `ws_client_message` | `ClientMessage` | §6.1 |
| `ws_server_message` | `ServerMessage` | §6.2 |
| `presence` | `Presence` | §11 |
| `input_info` | `GET /docs/{id}/inputs` の 1 要素 | §12 |

- ファイル: `docs/schema/{name}.schema.json`。`$id` は `https://hogandoc.dev/schema/collab-v1/{name}.schema.json`（名前空間であり、実在する URL ではない）。
- API: `GET /api/v1/schema` は `{ "protocol": "collab/v1", "schemas": { name: schema } }`、`GET /api/v1/schema/{name}` は単体。未知の名前は `404 not_found`。文書内容は含まないが、§14 の「`/health` 以外はトークン必須」に従う。hogandoc-server は `404` でよい。
- `add.value` / `update.patch` / `replace_document.document` は型で縛れない（`object.type` で変わる）ため schema 上は任意値。description で `document` schema の `$defs` を参照させている。
- `description` は Rust の doc コメント由来。単位（mm / pt）や座標系が分かるコメントを図形のフィールドに書くことが、そのまま LLM への説明になる。
- 呼ぶたびに値が変わる `serde(default = ...)`（`Run.id` の UUID）は `schemars(transform = schema_strip_default)` で `default` を落とす。生成物が非決定的になり、同期テストが常に落ちるため。
- 配布（plan_443）: `scripts/package-skill.sh` が SKILL.md と本書・schema・examples を
  `references/` に同梱した自己完結の skill を組み立て、`release.yml` の `skill` job が
  `hogandoc-editor-api-skill.zip` を Release に添付しつつ、公開リポジトリ
  `TomoyukiNakama/hogandoc` の `skills/hogandoc-editor-api/` へ push する。
