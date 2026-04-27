# household_mvp

家計簿MVPアプリ（Flutter + Supabase）

## セットアップ

```bash
flutter pub get
```

## 実行

Supabase の URL と Anon Key を `--dart-define` で渡して起動します。

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://<your-project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<your-anon-key>
```

## テスト

```bash
flutter test
```

## 静的解析

```bash
flutter analyze
```

## フォーマット

```bash
dart format .
```

## Supabase migration 適用

以下のSQLを Supabase SQL Editor で順番に実行してください。

> **配置場所**: migration ファイルは2箇所に分かれています。
> - リポジトリルート: `supabase/migrations/` — テーブル定義・スキーマ変更・トリガー
> - アプリ配下: `household-expenses-app/supabase/migrations/` — アプリ固有の設定テーブル

| # | ファイル | 配置場所 | 内容 |
|---|---------|---------|------|
| 1 | `20260215000000_create_categories_and_transactions.sql` | ルート | テーブル定義 + RLS + トリガー |
| 2 | `20260216000000_alter_user_id_defaults_and_composite_fk.sql` | ルート | 既存環境への差分適用（default / 複合FK） |
| 3 | `20260216100000_create_user_settings.sql` | アプリ配下 | ユーザー設定テーブル（表示通貨・為替レート） |
| 4 | `20260228000000_add_unit_price_and_quantity.sql` | ルート | 単価・個数カラム追加 + 既存データバックフィル |
| 5 | `20260228100000_seed_default_categories.sql` | ルート | 初期カテゴリ自動投入（トリガー + 既存ユーザーバックフィル） |
| 6 | `20260301000000_add_retention_policy.sql` | ルート | データ保持ポリシー（retention_config + expired_at + retention_logs） |
| 7 | `20260301100000_add_retention_functions.sql` | ルート | 保持ポリシーSQL関数群（dry_run / expire / purge / monthly_run） |

### migration 適用確認

以下のクエリで `user_id` の default と RLS policy を確認できます。

```sql
-- user_id default の確認（auth.uid() が設定されていること）
select table_name, column_name, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name in ('categories', 'transactions')
  and column_name = 'user_id';

-- RLS policy の確認
select tablename, policyname, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('categories', 'transactions')
order by tablename, policyname;
```

## 通貨設定

### 表示通貨の変更

設定画面の「表示通貨設定」セクションで、金額の表示通貨を変更できます。

- **対応通貨**: JPY (¥), USD ($), AUD (A$), EUR (€), GBP (£)
- **為替レート**: 手動で設定します（例: 1 USD = 150 JPY の場合、`150` と入力）
- **保存値**: すべての金額はJPY基準で保存されます。表示時にのみ換算されます

### 手動レート運用

1. 設定画面を開く
2. 表示通貨を選択（例: USD）
3. 為替レートを入力（例: `150.5`）— 「1 表示通貨 = ? JPY」の形式
4. 「通貨設定を保存」をタップ
5. ホーム画面に戻ると、金額が選択通貨で表示されます

> レート未設定の場合はJPY表示にフォールバックし、SnackBarで通知されます。

## UI/UX改善 (Step 6)

Step 6 で以下のUI改善が適用されています:

### デザイン基盤
- `lib/theme/app_theme.dart` にカラートークン・スペーシング・テーマを一元管理
- Material 3 テーマ（`ColorScheme.fromSeed`）を全画面で共有

### 状態表示の標準化
- `lib/widgets/state_views.dart` に共通部品（LoadingView / EmptyStateView / ErrorStateView）
- 全画面でローディング・空状態・エラー表示が統一

### 画面別改善
- **ホーム**: 収支を最上部に大きく強調、カテゴリ別内訳の色分け
- **取引編集**: フォームにprefixIcon追加、保存中の入力無効化、バリデーション明確化
- **設定**: 通貨設定/カテゴリ管理のセクション分離、アイコン付きヘッダー
- **ログイン**: prefixIcon追加

### 確認手順
```bash
flutter analyze   # 静的解析
flutter test      # 全テスト（104テスト）
```

## 取引削除 (Step 7)

取引編集画面から登録済み取引を削除できます。

### 操作手順
1. ホーム画面の取引一覧から対象取引をタップして編集画面を開く
2. AppBar右上の削除アイコン（ゴミ箱）をタップ
3. 確認ダイアログで「削除」をタップ
4. ホーム画面に戻り、一覧とサマリーが即時更新される

### 仕様
- 削除ボタンは**編集時のみ**表示（新規追加画面では非表示）
- 削除前に必ず確認ダイアログを表示（誤操作防止）
- 保存中・削除中は操作が無効化される（二重送信防止）
- 削除失敗時は既存エラーハンドリング方針に従い通知（認証切れ時は再ログイン導線）

## 支出の単価・個数入力 (Step 8)

支出登録時に「単価」と「個数」を分けて入力でき、合計金額が自動計算されます。

### 入力仕様
- **支出**: 単価と個数を入力 → 合計金額（= 単価 × 個数）が自動計算・表示
- **収入**: 従来どおり金額を直接入力
- 新規支出の個数はデフォルト `1`（従来の単発購入と同じ手間）

### データ設計
- `transactions` テーブルに `unit_price`（nullable）と `quantity`（default 1, check >= 1）を追加
- 集計・一覧・通貨換算は既存の `amount` カラムを基準とし、回帰なし

### マイグレーション
4. `20260228000000_add_unit_price_and_quantity.sql` — 単価・個数カラム追加 + 既存データバックフィル

### 確認手順
```bash
flutter analyze   # 静的解析
flutter test      # 全テスト（145テスト）
```

## 初期カテゴリ自動設定 (Step 9)

ユーザー作成時にデフォルトカテゴリが自動で作成されます。

### 初期カテゴリ一覧
- **支出（6件）**: 食費、水道光熱費、家賃、交通費、通信費、医療費
- **収入（2件）**: 給与、賞与

### 仕様
- 新規ユーザー登録時に `auth.users` トリガーで自動投入
- 既存ユーザーにはマイグレーション適用時にバックフィル（欠落分のみ補完）
- 初期カテゴリは通常カテゴリと同じ扱い（編集・削除可能）
- 同名・同タイプのカテゴリが既に存在する場合はスキップ（重複防止）

### セキュリティ
- `seed_default_categories()` / `on_auth_user_created()` は `REVOKE EXECUTE` で `anon` / `authenticated` からの直接呼び出しを禁止
- トリガー経由（`SECURITY DEFINER`）でのみ実行される

### 確認手順
```bash
flutter analyze   # 静的解析
flutter test      # 全テスト（157テスト）
```

DB側の検証手順（トリガー発火・冪等性・バックフィル）は `docs/tasks/step9_default_categories.md` の「SQL検証手順」セクションを参照してください。

## 分析グラフ (Step 10)

ホーム画面のAppBarにあるグラフアイコンから分析画面へ遷移できます。

### 機能
- **粒度切替**: 日別 / 月別 / 年別をセグメントボタンで切り替え
- **期間ナビゲーション**: 前後の月/年へ移動
- **カテゴリフィルタ**: 複数カテゴリを選択して絞り込み（チップで適用中フィルタを可視化）
- **棒グラフ**: 支出（赤）/ 収入（青）を並列表示（fl_chart使用）
- **合計カード**: フィルタ適用後の支出合計・収入合計・収支を表示

### 集計仕様
- 集計は `transactions.amount` を基準にクライアント側で実行
- グラフと合計カードは同一フィルタ条件で集計（整合性保証）
- 日別: 指定月内の各日をバケット化
- 月別: 指定年内の各月をバケット化（直近12ヶ月）
- 年別: 直近5年分のデータをバケット化

### 確認手順
```bash
flutter analyze   # 静的解析
flutter test      # 全テスト
```

## データ保持ポリシー (Step 11)

Supabase無料枠での長期運用に向け、取引データの保持年数を管理し、2段階削除（期限切れ化 → 猶予後の物理削除）を導入しています。

### ポリシー概要
- **保持期間**: Free運用 5年 / Paid運用 10年（`retention_config` テーブルで管理）
- **対象**: `transactions` テーブルのみ（カテゴリ等のマスタは対象外）
- **2段階削除**:
  1. 期限切れ化: `expired_at` にタイムスタンプを設定（通常画面から非表示になるが、データは残存）
  2. 物理削除: 猶予期間（デフォルト90日）経過後に DELETE
- **物理削除済みデータは自動復元しない**（必要ならバックアップ復元で対応）

### 運用手順（Supabase SQL Editor で実行）

```sql
-- 1. 現在の設定確認
SELECT * FROM retention_config;

-- 2. Dry-run（対象件数の事前確認、データ変更なし）
--    expire/purge/rehydrate の各対象件数を返す
SELECT * FROM retention_dry_run();

-- 3. 期限切れ化の実行（内部で rehydrate を先に実行）
SELECT * FROM retention_expire();

-- 4. 物理削除の実行（猶予期間超過分のみ）
SELECT * FROM retention_purge();

-- 5. 実行ログの確認
SELECT * FROM retention_logs ORDER BY executed_at DESC;

-- 一括実行（rehydrate → dry_run → expire → purge を順番に実行）
SELECT * FROM retention_run_monthly();
```

### 保持年数の変更

```sql
-- Free → Paid 切替時
UPDATE retention_config SET retention_years = 10 WHERE id = 1;

-- 変更後の影響確認（rehydrate_target_count で復帰対象件数を確認）
SELECT * FROM retention_dry_run();

-- 既に期限切れ化されたデータのうち、新しいポリシーで保持対象になるデータを復帰
SELECT * FROM retention_rehydrate();
```

> **注意**: 保持年数を延長した場合、`retention_rehydrate()` を実行することで、
> 既に期限切れ化されたが新ポリシーでは保持期間内のデータが自動的に復帰します。
> `retention_expire()` や `retention_run_monthly()` は内部で自動的に `rehydrate` を実行するため、
> 通常の月次運用では明示的な呼び出しは不要です。

### 月次定期実行

#### Supabase Pro 以上（pg_cron 利用可能）

```sql
-- 毎月1日 AM3:00 (UTC) に自動実行
SELECT cron.schedule(
  'retention-monthly',
  '0 3 1 * *',
  $$SELECT public.retention_run_monthly()$$
);

-- ジョブの確認
SELECT * FROM cron.job;

-- 実行履歴の確認
SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;

-- ジョブの削除
SELECT cron.unschedule('retention-monthly');
```

#### Supabase Free（手動実行）

毎月1回、SQL Editor から以下を実行してください:

```sql
SELECT * FROM retention_run_monthly();
SELECT * FROM retention_logs ORDER BY executed_at DESC LIMIT 5;
```

#### 実行失敗時

`retention_logs` の `success = false` のレコードを確認し、`error_message` を参照してください。
再実行は安全です（冪等性あり）。

### セキュリティ
- 全関数は `SECURITY DEFINER` + `REVOKE EXECUTE` + `SET search_path` で一般ユーザーからの直接呼び出しを遮断
- `retention_config` は認証済みユーザーの SELECT のみ許可
- `retention_logs` は RLS ポリシーなし（service_role のみ操作可）

## レシートOCR入力補助 (Step 12)

レシート画像から店名と合計金額を自動抽出し、支出入力の手間を削減します。

### 使い方
1. 支出追加画面で「レシート読み取り」ボタンをタップ
2. 「カメラで撮影」または「写真から選択」を選ぶ
3. OCR処理後、読み取り結果の確認ダイアログが表示される
4. 内容を確認し「適用する」をタップ → 単価・メモに自動反映
5. 必要に応じて内容を修正して保存

### 反映先
- **合計金額** → 単価フィールド（個数は1）
- **店名** → メモフィールド

### 仕様
- **オンデバイス処理**: 画像は端末外に送信・保存されません
- **対応言語**: 日本語レシートに最適化（google_mlkit_text_recognition使用）
- **対象項目**: 店名・合計金額のみ（明細行の自動分割は非対応）
- **信頼度表示**: 高/中/低の3段階で抽出精度を表示
- **1日上限**: 30回/日（ソフトリミット、アプリ再起動でリセット）

### 失敗時の動作
- OCR失敗・抽出失敗: SnackBarで通知し、手入力を継続可能
- 権限拒否: 画像取得がキャンセルされ、手入力にフォールバック
- 低信頼度: 確認ダイアログで警告表示し、適用後の確認を促す

### 確認手順
```bash
flutter analyze   # 静的解析
flutter test      # 全テスト（221テスト）
```

## レシートOCR Web対応・精度改善 (Step 13)

Step 12 のOCR機能をWebブラウザにも対応させ、抽出精度を改善しました。

### Web対応
- **ブラウザ内OCR**: tesseract.js を使用し、画像データを外部に送信せずにブラウザ内で処理
- **写真選択のみ**: Web版ではカメラ撮影は利用不可（画像ファイルの選択のみ）
- **初回利用時**: 日本語言語データ（約15MB）をダウンロード（2回目以降はキャッシュ済み）

### 精度改善
- **bbox活用**: OCRエンジンが返す位置・サイズ情報（bounding box）を活用したスコアリング
- **店名抽出**: 上位25%の位置 + フォントサイズ（bbox.height）で優先度を判定
- **合計金額抽出**: キーワード同一行最優先、右側近傍の金額を第2優先
- **除外強化**: 和暦日付（令和/平成）、10桁以上の連番（レシート番号等）を除外

### アーキテクチャ
- **3層構成**: OcrEngine（インフラ） / 抽出ロジック（純粋関数） / ReceiptOcrService（オーケストレーション）
- **条件付きインポート**: Mobile（ML Kit）/ Web（tesseract.js）をビルド時に自動切替
- **フォールバック**: bbox情報がない場合はテキストベースの既存ロジックを使用

### 確認手順
```bash
flutter analyze   # 静的解析
flutter test      # 全テスト（236テスト）
```

## Web画像取得の信頼性改善 (Step 14)

Webでレシート画像取得が失敗しやすい問題を解消し、失敗時の原因をUIで区別できるようにしました。

### 画像取得アダプタ
- **プラットフォーム別アダプタ**: OcrEngine と同じ条件付きインポートパターンで画像取得を分離
- **Mobile**: 従来の ImagePicker 経由（カメラ/ギャラリー選択、権限チェック）
- **Web**: ファイル形式チェック（JPEG/PNG、先頭バイト判定）＋サイズ上限チェック（10MB）

### 失敗分類とUIメッセージ
- **browserBlocked**: ブラウザ制約でファイル選択を開始できない場合
- **fileReadError**: 画像の読み込みに失敗した場合（ファイル破損等）
- **unsupportedFormat**: JPEG/PNG以外の画像を選択した場合
- **fileTooLarge**: 10MBを超える画像を選択した場合
- **permissionDenied**: カメラ/写真ライブラリへのアクセスが拒否された場合
- **unknown**: 未分類のエラー
- 各失敗時に「再試行」ボタン付き SnackBar を表示（permissionDenied は専用ダイアログ）

### 匿名メトリクス
- 失敗種別カウンタ（`debugPrint` ベース、PII非保存）

### 確認手順
```bash
flutter analyze   # 静的解析
flutter test      # 全テスト（277テスト）
flutter build web # Webビルド
```

## 画像前処理・ラベル優先度改善 (Step 18)

### 画像前処理（HEIC/HEIF 正規化）
- **モバイル**: `flutter_image_compress` により OCR 前に以下を自動適用
  - HEIC/HEIF → JPEG 変換
  - EXIF orientation 補正
  - 長辺 2048px リサイズ
  - JPEG 品質 85 正規化
- **Web**: パススルー（JPEG/PNG のみ受付のため不要）
- 前処理失敗時は元画像で OCR を続行（フォールバック）

### 重み付きラベル辞書
- `合計` / `税込合計` / `総合計`: weight 1.0（最優先）
- `ご請求額` / `お会計` / `TOTAL` / `Total`: weight 0.8
- `利用金額` / `決済額`: weight 0.6
- 複数ラベル一致時は weight が最も高いラベルの横の金額を採用

### HEIC 実画像の確認手順（モバイル実機）
1. iPhone で撮影した HEIC 画像を用意する
2. 同じ画像を JPEG に変換したものも用意する（Preview.app で書き出し等）
3. アプリの支出追加画面で「レシート読み取り」→ HEIC 画像を選択
4. 同じレシートの JPEG 画像でも同様に OCR を実行
5. 両者で店名・合計金額の抽出結果を比較し、HEIC でも安定して抽出できることを確認
6. デバッグログで `MobileImagePreprocessor: 前処理完了` が出力されていることを確認

### フォーマット検出
- マジックバイト判定: JPEG (FF D8), PNG (89 50 4E 47), HEIC/HEIF (ftyp ボックス)
- mimeType ヒントによるフォールバック判定

## サンプル起点精度改善 (Step 19)

### 画像品質緩和
- **モバイル**: ImagePicker の初期圧縮（imageQuality: 85）を撤廃
  - 長辺上限を 4096px に緩和（OOM 防止の安全上限のみ）
  - 最終的なリサイズ・品質管理は ReceiptImagePreprocessor に委譲
  - 二重圧縮（ImagePicker + Preprocessor）の解消により細文字の認識率向上

### ラベル正規化
- 空白分断ラベルの自動結合: `合 計` → `合計`
- 全角空白・タブも除去対象
- bbox 版ではトークン結合による検出もサポート: `合` + `計` → `合計`

### fallback 除外強化
- 追加した除外キーワード: `支払`, `PayPay`, `税率`, `対象`, `内消費税`, `電子マネー`, `カード`, `現金`
- これにより `PayPay支払 ¥670` や `税率 8%対象 ¥667` が合計として誤採用されにくくなる

### 簡易レシート領域 crop
- 前処理後の JPEG を `image` パッケージでデコードし、行/列の平均輝度からコンテンツ領域を検出
- レシート（白い紙）と背景（暗い面）の輝度差を利用して自動 crop
- crop 結果が元画像の 15% 未満、または 95% 超の場合はスキップ（フォールバック）
- crop 前後のサイズがログに出力される

### 観測ログ
- pick 後: format, bytes, dims（width x height）
- preprocess 後: format, bytes, dims, converted, applied steps
- OCR 後: token count
- 抽出結果: merchant, total, confidence
- ラベル候補検出時: label, weight, amount, line

### サンプル確認手順（IMG_1783.HEIC）
1. `docs/sample/IMG_1783.HEIC` を実機で用意する
2. アプリの支出追加画面で「レシート読み取り」→ サンプル画像を選択
3. 合計金額が `¥670` として抽出されることを確認
4. デバッグログで以下を確認:
   - `ReceiptOcrService: pick後` に format=heic, dims=WxH が出力される
   - `ReceiptOcrService: preprocess後` に format=jpeg, dims=WxH, converted=true が出力される
   - `MobileImagePreprocessor: crop` に crop 前後のサイズが出力される
   - `ReceiptOcrService: ラベル候補` に label="合計" amount=670 が出力される
5. crop 前後で OCR 結果を比較し、レシート本体の占有率向上を確認する

### Step 19 確認手順
```bash
flutter analyze   # 静的解析
flutter test      # 全テスト
flutter build web # Webビルド
```

## レシートOCR誤抽出ハードニング (Step 21)

Step 19 で扱いきれなかった「OCR は通るが誤った候補が勝つ」ケースをハードニングしました。
代表サンプルは `docs/sample/IMG_1783.jpg`（OCR 抽出はできるが `total=228215` / `merchant=どど ピ セブ フン - イ ルレ ル ブン` のような誤抽出が発生していた）。

### 主な改善点

#### 1. 不安全コンテキストの除外
- 伝票番号 `# 1234567890` / 電話番号 `03-1234-5678` / 会員コード行などを `isUnsafeAmountContext` で検出して fallback 候補から除外
- 通貨記号（`¥` / `\` / `円`）を持たない6桁以上の純数字行（伝票番号の典型形）も除外
- 既存の `totalExcludeKeywords`（`支払` / `PayPay` / `税率` 等）と独立した `amountUnsafeContextKeywords` で reject 理由を区別

#### 2. 合計ラベルの fuzzy 正規化
- OCR 部品分解の吸収:
  - `合 言十` / `合言十` → `合計`
  - `谷 計` / `台 計` → `合計`
- weight 0.7 でフォールバック適用（通常の `合計` weight 1.0 が当たらないときのみ）
- 誤吸収防止: 直近に `合計から` のような否定文脈がある場合はスキップ

#### 3. 合計ラベル直下行の金額ペアリング
- 湾曲したレシートで「合計」とその金額が同一行に乗らないケースに対応
- ラベル直下（Y=labelBottom 近傍）の amount を score 2.0 で採用
- 既存の Y-overlap チェック（labelHeight × 0.6）で税率行などとの混同を防止

#### 4. チェーン名の正規化（セブンイレブン）
- 部品断片の共起（`セブン` + `イレブン`、`セブ` + `ブン`、`レブン` 等）から正規化された店名を出力
- 1文字断片・純数字断片は誤マッチ防止のため棄却
- 既存の `merchantExcludeKeywords` を上書きするため、誤抽出された崩れトークンが採用されていてもチェーン名で置き換える

#### 5. 候補トレース機構（debug-only）
- `assert()` ベースのため release ビルドではコスト 0
- `ReceiptOcrService.lastCandidateTrace` で各候補の accept/reject 理由を確認可能
- ログ例:
  - `totalCandidate accepted reason=total_label_same_line amount=670 weight=1.0`
  - `totalCandidate rejected reason=unsafe_context amount=228215`
  - `merchantCandidate normalized chain=セブンイレブン source=fragments`

### IMG_1783.jpg の確認手順（モバイル実機）

1. `docs/sample/IMG_1783.jpg` を端末に転送
2. アプリの支出追加画面で「レシート読み取り」→ サンプル画像を選択
3. 確認ダイアログで以下を確認:
   - **店名**: `セブンイレブン`（または `セブン-イレブン` の正規化形式）
   - **合計金額**: `¥670`
4. デバッグログ（debugPrint）で以下が出力されることを確認:
   - 期待ログ:
     ```
     ReceiptOcrService.candidate: totalCandidate accepted reason=total_label_same_line amount=670 weight=1.0
     ReceiptOcrService.candidate: merchantCandidate normalized chain=セブンイレブン source=fragments
     ```
   - NG ログ（修正前の挙動、現在は出ないこと）:
     ```
     total=228215   ← 伝票番号の誤採用
     merchant=どど ピ セブ フン - イ ルレ ル ブン   ← OCR 崩れトークンの誤採用
     ```

### PII 非保存ポリシー（再掲）

- レシート画像・OCR 全文・抽出された店名は端末外に送信されない
- ログには PII を含めない:
  - format / bytes / dimensions / token count / label と weight / 採用された amount のみ
  - 候補トレースも理由（reason）と数値（amount）程度に留め、原文はログ化しない
- 監査ログとしての保存は行わない（trace は `_candidateTrace` に最後の1回分のみ揮発保持）

### Step 21 確認手順
```bash
flutter analyze   # 静的解析
flutter test      # 全テスト
flutter build web # Webビルド（Webパススルー経路に変更があるため必須）
```

## レシートOCR 実OCR再発ログ対応 (Step 22)

Step 21 修正後も `docs/sample/IMG_1783.jpg` の実OCRで `merchant=どど ピ セブ フン - イ ルレ ル ブン` / `total=651`（`商品代金` 由来の通貨付き金額が `fallback_currency_bbox` で採用される）誤抽出が再発したため、追加でハードニングしました。

### 主な改善点

#### 1. bottom-up 合計ラベル探索
- bbox 経路 (`extractTotalFromTokens`) の Phase 1 を pseudoLines 下→上の走査へ変更
- 同 weight の場合は最下部に出現したラベル候補を優先（レシート最終合計が下部に出ることに合致）
- text 経路 (`extractTotal`) も同様に下から走査
- `合計 ¥500 / PayPay支払 / 合計 ¥670` のような並びでは下の `670` を採用

#### 2. 商品行 fallback 抑制
- `totalFallbackExcludeKeywords` (`商品代金` / `商品` / `単価` / `点数` / `数量` / `対象商品`) を Phase 2 fallback 限定で除外
- `商品代金 ¥651` 単独行は通貨付きでも合計として採用しない
- ラベル候補が文書内に1つでも存在し金額ペアリング不能な場合、`fallback_suppressed_due_to_label_candidate` で `null` を返却（誤入力より未取得を優先）

#### 3. ロゴ崩れトークンの内部セグメント化
- `_segmentChainText` で空白・ハイフン類（`-`/`－`/`ー` など）・中黒・`/`・`|` を区切りにトークンを分割
- group A（seven 系）と group B（eleven 系）が**異なる**セグメントに出る場合のみチェーン名確定
- 同一セグメント内（例: `セブンスター`）の重複断片は不採用 → Round52 負例（`セブンスター` / `セブン銀行` / `セブンティーン` 等）を維持
- `ピ セブ フン - イ ルレ ル ブン` のように1トークンに潰れたケースでも `セブンイレブン` に正規化

### IMG_1783.jpg の確認手順（モバイル実機）

1. `docs/sample/IMG_1783.jpg` を端末に転送
2. アプリの支出追加画面で「レシート読み取り」→ サンプル画像を選択
3. 確認ダイアログで以下を確認:
   - **店名**: `セブンイレブン`
   - **合計金額**: 実レシートの `合計` 行の金額（`商品代金` 由来の `¥651` ではない）
4. デバッグログ（debugPrint）で以下を確認:
   - 期待ログ（OK）:
     ```
     ReceiptOcrService.candidate: totalCandidate accepted reason=total_label_same_line amount=...
     ReceiptOcrService.candidate: merchantCandidate normalized chain=セブンイレブン source=fragments
     ```
   - NG ログ（修正前の挙動、現在は出ないこと）:
     ```
     totalCandidate accepted reason=fallback_currency_bbox amount=651   ← 商品代金 ¥651 の誤採用
     merchant=どど ピ セブ フン - イ ルレ ル ブン                          ← セグメント化前の生文字列
     ```
5. 合計ラベルが完全にOCR崩れて検出できないケースでは、`商品代金 ¥651` を採用せず未取得（手入力）に戻ることを確認

### PII 非保存ポリシー（再掲）

- 候補トレースは reason / amount / weight / label 種別 / line_idx に限定し、原文行は出さない
- `商品代金` の reject 理由は `product_line_fallback`、ラベル候補存在時の抑制理由は `fallback_suppressed_due_to_label_candidate` として観測可能

### Step 22 確認手順
```bash
flutter analyze
flutter test
flutter build web
```

## レシートOCR ラベル近傍探索 (Step 23)

Step 22 の `fallback_suppressed_due_to_label_candidate` で `total=null` になる実OCRログ（`merchant=セブンイレブン` 正規化済みだが、`合計` ラベルが OCR で同一行/直下行に金額を捉えられず未取得）に対応して、ラベル候補の上下2行を対象に金額をスコア探索する処理を追加しました。

### 主な改善点

#### 1. ラベル近傍金額探索 (`_searchNearbyTotalAmounts`)
- Phase 1 通常ペアリングが空振りした場合、検出済みラベル候補（`labelCandidates`）の上下2行を対象に金額を再探索
- 位置スコア: 同一行 2.5 / 直下 2.2 / 直上 1.8 / ±2行 1.4
- 加算: ラベル weight × 0.5、ラベルより右なら +0.5 / 左or同位は +0.1、`¥`/`円` 通貨記号 +0.2
- Y距離ペナルティ: ラベル中心と金額中心のY距離 / ラベル高さ × 0.05（最大 0.4）
- スコア閾値 1.5 を超える最高スコアの金額を採用（同 weight 同士の比較）
- Step 22 の `fallback_suppressed_due_to_label_candidate` ガードは維持。近傍探索でヒットすれば `null` ではなく値を返す

#### 2. 近傍候補の除外
- `isUnsafeAmountContext`（連番・電話・郵便など）でフィルタ
- `totalExcludeKeywords` + `totalFallbackExcludeKeywords`（商品代金 / PayPay支払 / 税率 / 単価 / 点数 等）を含む行は除外
- `_isFallbackSafeAmount` で通貨記号がない金額（連番混在のリスク）を除外
- 同一行ではラベルより左の金額（バーコード等）を採用しない

#### 3. PII 非保存トレース拡張
- `label_candidate_found`: ラベル候補検出時の line_idx / weight
- `total_label_nearby`: 近傍探索採用時の amount / weight
- `nearby_amount_rejected`: 除外理由 `excluded_context` / `unsafe_context` / `no_currency_mark` / `below_threshold`
- 既存 `fallback_suppressed_due_to_label_candidate`: 近傍探索もヒットしなかった場合のみ出る

#### 4. チェーン名 source トレース（Step22 N-2 統合）
- `merchantCandidate normalized chain=... source={exact|fragments|segmented_fragments}`
- `segmented_fragments`: 単一トークン内の `_segmentChainText` 分割によりA/B両群を同一トークンから抽出した経路
- `fragments`: 複数トークンに跨る通常の断片合成
- 監査時に「Step22 セグメント化が実際に機能したか」を観測可能

### 確認手順（モバイル実機）

1. `docs/sample/IMG_1783.jpg` のように `合計` ラベルが上下行に分離した実レシートを支出追加画面で読み取り
2. デバッグログで以下を確認:
   - 期待ログ（OK）:
     ```
     ReceiptOcrService.candidate: totalCandidate label_candidate_found label=合計 weight=1.0 line_idx=2
     ReceiptOcrService.candidate: totalCandidate accepted reason=total_label_nearby amount=670 weight=1.0
     ```
   - NG ログ（修正前の挙動、現在は出ないこと）:
     ```
     totalCandidate fallback_suppressed_due_to_label_candidate   ← 近傍探索も空振りの場合のみ許容
     ```
3. `商品代金 ¥651` のみで `合計` 行が完全に欠落するレシートでは、`fallback_suppressed_due_to_label_candidate` のまま `null` 返却（手入力に戻る）であることを確認

### Step 23 確認手順
```bash
flutter analyze
flutter test
flutter build web
```

## レシートOCR 近傍探索 偽陽性抑止 (Step 24)

Step 23 で追加した `total_label_nearby` が、実OCRで税額/内消費税系の孤立小額 `148`（通貨記号なし）を採用してしまう再発に対応しました。あわせて、OCRが `セブン` を `セフン` と誤読するケース（`雪 セフン - イ ル ブ ン`）の店名正規化も追加しています。

### 主な改善点

#### 1. 弱い小額のガード (`weak_small_amount` / `weak_alignment`)
- `_searchNearbyTotalAmounts()` と `total_label_below_line` 直下行ペアリングに、通貨記号なし `amount <= 999` 専用の追加ガードを実装
- 採用条件:
  - 同一行（delta=0）でラベル token より右側にある、または
  - 強い列整列（近傍領域の他の金額 token 右端 X 中央値と `max(40px, 推定画像幅 * 0.03)` 相当以内）が確認できる
- 2行差（|delta| ≥ 2）の通貨記号なし小額は原則 reject (`weak_alignment`)
- 既存の `_isFallbackSafeAmount()` のグローバル仕様変更は避け、合計ラベル起点経路内に閉じた追加ガード

#### 2. 隣接文脈による除外 (`neighbor_excluded_context`)
- 通貨記号なし小額のみ、候補行の前後1行に以下があれば棄却:
  - 税系: `税率` / `対象` / `内税` / `外税` / `消費税` / `税額`
  - 商品系: `商品代金` / `商品` / `単価` / `点数` / `数量` / `対象商品`
  - 支払系: `PayPay` / `支払` / `現金` / `カード` / `電子マネー` / `預り` / `お預り` / `お釣り` / `おつり`
- 税系除外の緩和は、候補行自身に `合計(税込)` / `税込合計` / `ご請求(税込)` のような強い合計ラベルと税系語が共存する場合に限定
- 隣接行に通常の `合計` ラベルがあるだけでは税系除外を緩和しない
- 通貨記号付き金額は隣接文脈除外の対象外（Step23 の既存挙動を維持）

#### 3. trace 拡張
- 採用 trace: `total_label_nearby amount=... weight=... line_idx=... label_line_idx=... delta=... has_currency=... score=...`
- 棄却理由: `weak_small_amount` / `weak_alignment` / `neighbor_excluded_context`
- PII 非保存（行原文・OCR全文・住所・電話番号・会員番号は出さない）

#### 4. 店名正規化: `セフン` 系 OCR 揺れ対応
- `MerchantChainRule` のセブンイレブン group A に `セフン` を追加（2文字以上のまとまりとしてのみ認定）
- `_matchChainRuleWithSource()` の group B 検査で「同一 source idx の nonA セグメント連結」マッチを補助追加
  - `雪 セフン - イ ル ブ ン` のように1トークンが1文字単位に分かれても `イルブン` 連結で `ブン` を再構成可能
- 単独 `フン` だけでは group A 不成立 → `フン イ ル ブン` は誤補正しない
- `セブン銀行` / `セブンスター` / `セブンティーンアイス` / `セブンカフェ` 等の負例は維持

### 確認手順（モバイル実機）

1. `合計` ラベル直近に税額/内税系の孤立小額（通貨記号なし）が並ぶレシートを支出追加画面で読み取り
2. デバッグログで以下を確認:
   - 期待ログ（OK）:
     ```
     ReceiptOcrService.candidate: totalCandidate label_candidate_found label=合計 weight=1.0 line_idx=...
     ReceiptOcrService.candidate: totalCandidate nearby_amount_rejected reason=weak_small_amount line_idx=... amount=148 has_currency=false delta=...
     ReceiptOcrService.candidate: totalCandidate accepted reason=total_label_nearby amount=<実合計> ... has_currency=true score=...
     ```
   - または安全な合計が無い場合:
     ```
     ReceiptOcrService.candidate: totalCandidate rejected reason=fallback_suppressed_due_to_label_candidate
     ReceiptOcrService: 抽出結果 ... total=null
     ```
   - NG ログ（修正前の挙動、現在は出ないこと）:
     ```
     totalCandidate accepted reason=total_label_nearby amount=148   ← 通貨記号なし小額の誤採用
     merchant=雪 セフン - イ ル ブ ン                                ← 正規化失敗
     ```
3. 結果確認ダイアログで以下を確認:
   - 店名: `セブンイレブン`（`セフン` 系の OCR 揺れも吸収）
   - 合計金額: 実レシート上の `合計` 行金額、または安全に取れない場合は空欄

### Step 24 確認手順
```bash
flutter analyze
flutter test
flutter build web
```

## レシートOCR 合計未取得 原因可視化 (Step 25)

Step24後の実OCRで `merchant=セブンイレブン` まで正規化でき、`230` / `148` の誤採用も防げている一方、`total=null` になるケースを分析するための候補スキャンtraceを追加します。Step25では抽出条件を緩めず、正しい合計金額tokenがOCR結果に存在するかを判定できるログ整備に限定します。

### 目的

- `合計` ラベル候補が存在するのに `total=null` になった場合、正しい金額tokenが「OCR上に無い」「探索範囲外」「除外文脈」「弱小額/列整列ガード棄却」のどれに近いかを切り分ける
- `230` / `148` / `商品代金` fallback の誤採用防止は維持する
- `fileTooLarge` は画像取得/入力サイズの別問題として扱い、合計抽出ロジックの原因分析と混同しない

### 期待trace例

```text
ReceiptOcrService.candidate: totalCandidate scan_start label_line_idx=6 window=2 token_count=10
ReceiptOcrService.candidate: totalCandidate scan_line line_idx=4 label_line_idx=6 delta=-2 amount_candidates=[230] has_currency=false excluded=false weak_small=true neighbor_excluded=false right_aligned=false route=total_label_nearby classification=would_reject_weak_small_amount
ReceiptOcrService.candidate: totalCandidate scan_line line_idx=5 label_line_idx=6 delta=-1 amount_candidates=[148] has_currency=false excluded=false weak_small=true neighbor_excluded=true right_aligned=false route=total_label_nearby classification=would_reject_neighbor_context
ReceiptOcrService.candidate: totalCandidate scan_summary label_line_idx=6 total_amount_tokens=3 accepted_candidates=0 rejected_candidates=3
ReceiptOcrService.candidate: totalCandidate amount_inventory_start reason=label_present_total_null max_candidates=20
ReceiptOcrService.candidate: totalCandidate amount_inventory line_idx=12 delta_from_label=6 amount=670 has_currency=true excluded=false weak_small=false y_bucket=bottom x_bucket=right classification=outside_nearby_window
ReceiptOcrService.candidate: totalCandidate amount_inventory_summary total_candidates=5 emitted=5 capped=false
```

### 分類（classification）固定文字列

- `would_accept_same_line` / `would_accept_below_line` / `would_accept_nearby`
- `would_reject_excluded_context` / `would_reject_weak_small_amount` / `would_reject_neighbor_context`
- `would_reject_no_currency_mark` / `would_reject_serial_or_receipt_number`
- `outside_nearby_window` / `not_amount`

### inventory 出力条件

- `合計` 系のラベル候補が 1 件以上検出された × 最終 `totalAmount=null` のときだけ出力する
- 安全に合計が確定したケースでは inventory を出さない（ノイズ抑止）
- `fileTooLarge` などの画像取得失敗は OCR 抽出 trace と別系統で記録する

### PII非保存ルール

- traceにOCR行原文、OCR全文、住所、電話番号、会員番号、伝票番号全文を出さない
- 出してよい情報は `line_idx`, `label_line_idx`, `delta`, `amount`, `has_currency`, `route`, `excluded_context`, `weak_small`, `neighbor_excluded`, bbox要約（`x_bucket=left|center|right` / `y_bucket=top|mid|bottom`）、分類名に限定する

### Step 25 確認手順

```bash
flutter test test/receipt_ocr_test.dart --plain-name "Step25"
flutter test test/receipt_ocr_test.dart --plain-name "Step24"
flutter analyze
flutter test
flutter build web
```

## トラブルシューティング

### RLS 42501 エラー（カテゴリ追加/取引保存が失敗する）

「権限エラーが発生しました」または「セッションの有効期限が切れました」と表示される場合:

1. **セッション切れの場合**: 再ログインしてください
2. **セッション有効なのに 42501 の場合**: DBスキーマのドリフト（migration未適用）が原因です
   - 上記の「migration 適用確認」クエリを実行し、`column_default` が `auth.uid()` になっているか確認
   - 未設定の場合は `20260216000000_alter_user_id_defaults_and_composite_fk.sql` を再適用してください
