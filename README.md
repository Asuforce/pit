# pit - Performance Improving Training

1つのECサイトアプリケーションを段階的に改善しながら、Webアプリケーションのパフォーマンス最適化を学習する実践的な学習環境です。

## プロジェクト構成

```
backend/          # Rails + GraphQL API
frontend/         # Next.js + React（準備中）
docker/           # Docker設定（MySQL, Redis）
docs/             # 段階的改善ガイド
tools/
  ├── k6/         # 負荷テストシナリオ
  ├── scripts/    # 分析スクリプト
  └── benchmarks/ # ベンチマークツール
```

## クイックスタート

### 1. 環境構築

```bash
# Dockerイメージをビルド
make build

# コンテナ起動
make up

# Database初期化
make db-setup
```

Rails: http://localhost:3000
Adminer: http://localhost:8080

### 2. 学習開始

各フェーズのドキュメントを `docs/` から読んで、段階的に改善を進めます。

## 学習フロー

アプリケーションには意図的なパフォーマンス問題が含まれています。各フェーズで問題を発見・改善していきます。

### Phase 1: 環境セットアップ
`docs/01-setup.md`

- Docker + Rails + MySQL + Redis の構築
- パフォーマンス計測ツール（rack-mini-profiler, bullet）の設定
- ベースラインパフォーマンスの計測

### Phase 2: N+1問題の解決
`docs/02-n-plus-one.md`

- N+1問題の仕組みを理解
- includes/preload による最適化
- GraphQL batch_loader の実装
- 改善: クエリ数 2000+ → 3に削減

### Phase 3: キャッシング戦略
`docs/03-caching.md`

- Fragment Cache と Russian Doll Caching
- Redis キャッシュストアの設定
- キャッシュ無効化タイミングの設計
- 改善: レスポンス時間 95%削減

### Phase 4: GraphQL最適化
`docs/04-graphql-optimization.md`

- GraphQL DataLoader/batch_loader
- クエリ複雑度制限
- Fragment の活用
- 改善: GraphQL クエリ数 1000+ → 2に削減

### Phase 5: フロントエンド最適化
`docs/05-frontend-optimization.md`

- Code Splitting と lazy loading
- 画像最適化（next/image）
- Core Web Vitals 改善
- 改善: バンドルサイズ 50%削減、LCP 3.5s → 2.0s

### Phase 6: データベース最適化
`docs/06-database-optimization.md`

- EXPLAIN分析とインデックス設計
- スロークエリログ分析
- InnoDB チューニング
- 改善: クエリ実行時間 100ms → 2ms

### Phase 7: 負荷テスト
`docs/07-load-testing.md`

- k6 Smoke/Load/Stress/Spike テスト
- パフォーマンスボトルネックの特定
- 改善効果の計測と検証

## よく使うコマンド

```bash
# Rails console
make rails-shell

# Database操作
make db-migrate
make db-seed
make mysql-shell

# パフォーマンステスト
make smoke-test      # 基本動作確認
make load-test       # 通常負荷テスト
make stress-test     # 限界テスト
make spike-test      # スパイクテスト

# ログ確認
make logs
make logs-slow-query # スロークエリログ

# 環境操作
make down            # コンテナ停止
make clean           # 完全リセット
```

詳しくは `make help` で確認できます。

## パフォーマンス改善チェックリスト

各フェーズでの実装項目はこちらを参照：

`tools/OPTIMIZATION_CHECKLIST.md`

## 計測結果の比較

改善過程の計測結果は `logs/` ディレクトリに保存されます：

```
logs/
├── baseline.txt                # Phase 1: ベースライン
├── phase2-before.txt           # Phase 2: 改善前
├── phase2-after.txt            # Phase 2: 改善後
├── load-baseline.json          # 負荷テストベースライン
└── ...
```

## アプリケーション機能

ECサイトの基本機能を実装：

- 商品一覧（カテゴリ別、検索、ページネーション）
- 商品詳細（関連商品、レビュー）
- カート機能
- 注文履歴
- レビュー機能（集計機能付き）

各機能に意図的なパフォーマンス問題が含まれており、段階的に改善していきます。

## 技術スタック

### バックエンド
- Ruby 3.2.0
- Rails 7.0
- GraphQL 2.0
- MySQL 8.0
- Redis 7.0

### フロントエンド（準備中）
- TypeScript
- React
- Next.js

### パフォーマンス計測
- rack-mini-profiler
- bullet
- k6
- Lighthouse

## 参考資料

各ドキュメントに詳細なコード例と説明が含まれています。

- [EXPLAIN分析ガイド](docs/06-database-optimization.md)
- [GraphQL最適化パターン](docs/04-graphql-optimization.md)
- [React最適化パターン](docs/05-frontend-optimization.md)

## ライセンス

MIT
