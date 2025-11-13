# パフォーマンス改善チェックリスト

各フェーズで実施すべき項目を記載しています。各項目を確認したら✓をつけてください。

## Phase 1: 環境セットアップ

### Docker & Rails環境
- [ ] docker compose が起動している
- [ ] Rails サーバーが localhost:3000 でアクセス可能
- [ ] MySQL が接続されている
- [ ] Redis が接続されている
- [ ] Adminer が localhost:8080 で動作している

### 計測ツール設定
- [ ] rack-mini-profiler がインストールされている
- [ ] bullet がインストールされている
- [ ] k6 がインストールされている

## Phase 2: N+1問題の検出と解決

### 問題検出
- [ ] rack-mini-profiler で商品一覧のクエリ数を確認
- [ ] ベースラインクエリ数を記録（目安: 500以上）
- [ ] bullet がN+1警告を出している
- [ ] 計測ログを logs/phase2-before.txt に保存

### 改善実装
- [ ] ProductsController に includes を追加
- [ ] 関連テーブル（category, reviews）を指定
- [ ] クエリ数が 5以下に削減されたか確認
- [ ] レスポンス時間が 10倍以上改善されたか確認
- [ ] 計測ログを logs/phase2-after.txt に保存

### GraphQL対応
- [ ] GraphQL Query で N+1 問題が発生していることを確認
- [ ] batch_loader/Dataloader を実装
- [ ] クエリ数が削減されたか確認

## Phase 3: キャッシング戦略

### Fragment Cache 実装
- [ ] 商品リストにキャッシュキーを追加
- [ ] キャッシュ有効期限を 1時間 に設定
- [ ] 2回目アクセスで高速化することを確認
- [ ] レスポンス時間を logs/phase3-fragment.txt に記録

### Russian Doll Caching
- [ ] 親キャッシュ（全商品一覧）を実装
- [ ] 子キャッシュ（個別商品）を実装
- [ ] 1商品更新時に該当キャッシュのみ無効化されるか確認
- [ ] 他の商品キャッシュが有効のままか確認

### Redis 検証
- [ ] Redis への接続を確認（redis-cli ping）
- [ ] キャッシュデータが Redis に格納されているか確認
- [ ] キャッシュヒット率を計測

## Phase 4: GraphQL最適化

### Dataloader 実装
- [ ] CategoryLoader が実装されている
- [ ] ReviewLoader が実装されている
- [ ] バッチ処理でクエリが削減されているか確認

### クエリ複雑度制限
- [ ] max_query_complexity を 50 に設定
- [ ] max_query_depth を 7 に設定
- [ ] 複雑すぎるクエリが拒否されるか確認

### GraphQL Fragment活用
- [ ] 共通フィールドが Fragment で定義されている
- [ ] Fragment 使用でクエリが簡潔になったか確認

## Phase 5: フロントエンド最適化

### Code Splitting
- [ ] 商品詳細ページが動的import に変更されている
- [ ] ネットワークタブでバンドルが分割されているか確認
- [ ] メインバンドルサイズが削減されたか確認

### 画像最適化
- [ ] 全商品画像が next/image に変更されている
- [ ] width と height が指定されている
- [ ] WebP 形式への自動変換が行われているか確認

### フォント最適化
- [ ] next/font が設定されている
- [ ] フォントの preload が有効か確認

### Core Web Vitals
- [ ] Lighthouse でスコアを計測
- [ ] LCP（Largest Contentful Paint）を記録
- [ ] FID（First Input Delay）を記録
- [ ] CLS（Cumulative Layout Shift）を記録
- [ ] 改善目標: LCP < 2.5s, FID < 100ms, CLS < 0.1

## Phase 6: データベース最適化

### EXPLAIN 分析
- [ ] `EXPLAIN SELECT * FROM products` でタイプを確認
- [ ] 改善前: type = ALL, rows = 全行数
- [ ] インデックス追加後: type = ref, rows < 1000

### インデックス設計
- [ ] `products` テーブルに `idx_category_id` を追加
- [ ] 複合インデックス `idx_category_price` を追加
- [ ] カバリングインデックスを設計

### スロークエリ検出
- [ ] slow_query_log が有効か確認
- [ ] long_query_time = 1秒 に設定
- [ ] 遅いクエリが記録されるか確認
- [ ] スロークエリログをレビュー

### クエリ最適化
- [ ] YEAR() 関数の使用を避けた（インデックス活用）
- [ ] 複雑な JOIN を簡潔に
- [ ] WHERE 句で適切に絞り込まれているか確認

## Phase 7: 負荷テスト

### Smoke Test
- [ ] `make smoke-test` が成功する
- [ ] 全リクエストの status = 200
- [ ] エラー率 = 0%

### Load Test
- [ ] ユーザー100で 5分間安定実行
- [ ] p(95) response time < 1000ms
- [ ] 失敗率 < 5%
- [ ] ベースライン結果を logs/load-baseline.json に保存

### Stress Test
- [ ] ユーザー400での動作確認
- [ ] p(99) response time < 3000ms
- [ ] システムが gracefully degrade するか確認

### Spike Test
- [ ] 1000ユーザーへの急増に対応
- [ ] システムが復帰するか確認
- [ ] エラー数が許容範囲か確認

## 全体確認

### パフォーマンス改善指標
- [ ] レスポンス時間が 50%以上改善されている
- [ ] クエリ数が 80%以上削減されている
- [ ] p(95) response time が目標を達成している
- [ ] エラー率が 1%以下である

### コード品質
- [ ] 全テストが成功している
- [ ] コード的負債がドキュメント化されている
- [ ] 改善履歴がコミットメッセージに記録されている

### ドキュメント
- [ ] 各フェーズのドキュメントを完了した
- [ ] パフォーマンス計測結果を記録した
- [ ] 改善前後の比較表を作成した

## メモ

改善過程での気づき、ボトルネック、今後の改善案をここに記録：

```
[記録例]
- Phase 2: N+1問題で 2000+ のクエリが実行されていた
- Phase 3: Fragment cache で 95% の高速化を達成
- Phase 6: category_id インデックスで query_time が 100ms → 2ms に削減
```
