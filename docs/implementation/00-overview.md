# PIT実装ガイド - 全体概要

> **学習ガイドとの関係**: 各フェーズの理論的背景は `../` ディレクトリの学習ガイド（`01-setup.md` ～ `07-load-testing.md`）を参照してください。本ドキュメントは実装に特化した詳細マニュアルです。詳しくは [`../README.md`](../README.md) を参照。

## プロジェクト構造

PIT (Performance Improving Training) は、Webアプリケーションのパフォーマンス最適化について実践的に学ぶプロジェクトです。バックエンド（Rails + GraphQL）とフロントエンド（Next.js）から構成されています。

```
pit/
├── backend/               # Rails アプリケーション
│   ├── app/
│   │   ├── models/       # データベースモデル
│   │   ├── graphql/      # GraphQLスキーマと型定義
│   │   ├── controllers/  # APIエンドポイント
│   │   └── views/        # APIレスポンステンプレート
│   ├── db/
│   │   ├── migrate/      # マイグレーション
│   │   └── seeds.rb      # シードデータ
│   ├── Dockerfile
│   ├── Gemfile
│   └── docker-compose.yml
├── frontend/             # Next.js アプリケーション
│   ├── pages/
│   ├── components/
│   ├── public/
│   └── next.config.js
└── docs/                 # ドキュメント
    ├── 01-setup.md
    ├── 02-n-plus-one.md
    ├── 03-caching.md
    ├── 04-graphql-optimization.md
    ├── 05-frontend-optimization.md
    ├── 06-database-optimization.md
    ├── 07-load-testing.md
    └── implementation/   # 実装ガイド（このディレクトリ）
```

## 7つのフェーズと学習内容

### Phase 1: セットアップ
**目的**: 開発環境の構築とベースラインパフォーマンスの計測

**学習内容**
- Docker環境の構築と管理
- Rails アプリケーションの基本設定
- GraphQLの初期設定
- パフォーマンス計測ツールの導入
- ベースラインメトリクスの記録

**実装成果物**
- Docker Composeで起動するRails + MySQL + Redis環境
- GraphQLエンドポイントが動作するRailsアプリケーション
- 意図的なパフォーマンス問題を含むサンプルコード

**必要な技術**
- Docker / Docker Compose
- Rails の基礎知識
- SQL の基礎知識

---

### Phase 2: N+1問題の解決
**目的**: データベースクエリの効率化とN+1問題の検出・解決方法を習得

**学習内容**
- N+1問題の仕組みと影響
- `includes` / `preload` / `eager_load` の使い分け
- GraphQL DataLoaderパターンの実装
- 問題検出ツール（bullet）の活用

**前提条件**
- Phase 1 完了

**実装成果物**
- ProductとCategoryの関連設定
- GraphQL DataLoader実装
- bulletによるN+1警告の解決

**対象ファイル**
- `app/models/product.rb`
- `app/models/category.rb`
- `app/graphql/types/product_type.rb`
- `app/graphql/loaders/category_loader.rb`

---

### Phase 3: キャッシング戦略
**目的**: Redisを使った分散キャッシング実装とキャッシュ無効化タイミングの設計

**学習内容**
- Rails キャッシュの種類と使い分け
  - Page Cache
  - Action Cache
  - Fragment Cache
  - Russian Doll Caching
- Redis分散キャッシュの運用
- キャッシュキーの設計
- キャッシュ無効化タイミングの決定

**前提条件**
- Phase 1, 2 完了

**実装成果物**
- Redis キャッシュストア設定
- Fragment Cache の実装
- Russian Doll Caching の実装例
- キャッシュ無効化ロジック

**対象ファイル**
- `config/environments/development.rb`
- `config/environments/production.rb`
- `app/controllers/api/products_controller.rb`
- `app/models/product.rb` (after_update callback)

---

### Phase 4: GraphQL最適化
**目的**: GraphQLクエリの最適化とN+1問題の根本解決

**学習内容**
- GraphQL DataLoaderの詳細実装
- Batch Loaderの使用方法
- クエリ複雑度の制限
- クエリ計画と実行計画の分析

**前提条件**
- Phase 1, 2, 3 完了

**実装成果物**
- graphql-batch gem の統合
- 複数の Loader 実装
- クエリ複雑度制限の設定
- GraphQL インストロスペクション対応

**対象ファイル**
- `app/graphql/pit_schema.rb`
- `app/graphql/loaders/batch_loader.rb`
- `app/graphql/types/query_type.rb`

---

### Phase 5: フロントエンド最適化
**目的**: Core Web Vitalsの改善とNext.jsの最適化

**学習内容**
- Core Web Vitals指標の理解
  - LCP (Largest Contentful Paint)
  - FID (First Input Delay)
  - CLS (Cumulative Layout Shift)
- Code Splitting と Dynamic Imports
- 画像最適化
- フォント最適化
- React メモ化パターン

**前提条件**
- Phase 1 ～ 4 完了
- Next.js プロジェクトの初期構築完了

**実装成果物**
- Next.js の最適化設定ファイル
- コンポーネントのコード分割実装
- 画像最適化設定
- Web Vitals計測ライブラリの統合

**対象ファイル**
- `frontend/next.config.js`
- `frontend/pages/products/index.tsx`
- `frontend/components/ProductCard.tsx`
- `frontend/lib/web-vitals.ts`

---

### Phase 6: データベース最適化
**目的**: MySQLクエリの効率化とインデックス設計

**学習内容**
- EXPLAIN コマンドの使用方法
- インデックス設計のベストプラクティス
  - 単一カラムインデックス
  - 複合インデックス
  - カバリングインデックス
- InnoDB設定のチューニング
- スロークエリログの分析

**前提条件**
- Phase 1 ～ 5 完了

**実装成果物**
- インデックス設計ドキュメント
- マイグレーション実装
- MySQLチューニング設定
- スロークエリ分析結果

**対象ファイル**
- `db/migrate/*_add_indexes.rb`
- `docker-compose.yml` (MySQL設定)
- `config/my.cnf` (またはDockerイメージ内設定)

---

### Phase 7: 負荷テスト
**目的**: パフォーマンス改善効果の測定と検証

**学習内容**
- k6を使った負荷テストシナリオ作成
- テスト種別の使い分け
  - Smoke Test
  - Load Test
  - Stress Test
  - Spike Test
- パフォーマンスメトリクスの収集と分析
- ボトルネック特定と改善効果測定

**前提条件**
- Phase 1 ～ 6 完了

**実装成果物**
- k6テストスクリプト一式
- ベースラインメトリクス記録
- 改善前後の比較分析
- 本番環境用テストシナリオ

**対象ファイル**
- `k6/smoke-test.js`
- `k6/load-test.js`
- `k6/stress-test.js`
- `k6/spike-test.js`

---

## 実装の前提条件

### システム要件
- Docker と Docker Compose
- Node.js 18以上（フロントエンド開発時）
- Ruby 3.2以上（ローカル開発時）
- MySQL 8.0以上

### 事前準備
1. リポジトリのクローン
2. Docker のインストールと起動
3. `.env` ファイルの作成

### 推奨される学習順序

```mermaid
Phase 1: Setup
    ↓
Phase 2: N+1問題の検出と解決
    ↓
Phase 3: キャッシング戦略
    ↓
Phase 4: GraphQL最適化
    ├─ (並行可能)
    ↓
Phase 5: フロントエンド最適化
    ↓
Phase 6: データベース最適化
    ↓
Phase 7: 負荷テスト（全段階を含む）
```

**重要な注意**
- 各フェーズは前のフェーズの知識を前提としています
- Phase 7（負荷テスト）は全ての実装完了後の最終検証です
- 各フェーズでのパフォーマンス改善は、次のフェーズで確認することで学習効果が高まります

---

## 各ガイドの使用方法

このディレクトリには、各フェーズの詳細実装ガイドが存在します：

- `01-setup-implementation.md`: Phase 1の詳細手順
- `02-n-plus-one-implementation.md`: Phase 2の詳細手順
- `03-caching-implementation.md`: Phase 3の詳細手順
- `04-graphql-implementation.md`: Phase 4の詳細手順
- `05-frontend-implementation.md`: Phase 5の詳細手順
- `06-database-implementation.md`: Phase 6の詳細手順
- `07-load-testing-implementation.md`: Phase 7の詳細手順

各ドキュメントは以下の構成になっています：

1. **概要**: フェーズの目的と学習内容
2. **前提条件**: 必要な環境とスキル
3. **実装ステップ**: 段階的な実装手順
4. **コード例**: 実装例とベストプラクティス
5. **動作確認**: テストと検証方法
6. **トラブルシューティング**: よくある問題と解決策

---

## パフォーマンス計測の継続

各フェーズを完了した後は、以下のメトリクスを記録することで、改善効果を定量的に把握できます：

```json
{
  "phase": 1,
  "timestamp": "2024-01-15T10:00:00Z",
  "metrics": {
    "average_response_time_ms": 450,
    "p95_response_time_ms": 850,
    "queries_per_request": 15,
    "cache_hit_rate_percent": 0,
    "memory_usage_mb": 256
  }
}
```

Phase 7の負荷テストでは、これらのメトリクスを比較して改善効果を定量化します。

---

## サポートとリソース

各フェーズで困った場合：

1. 対応するドキュメント（`01-setup.md` など）を確認
2. 実装ガイドの「トラブルシューティング」セクションを参照
3. Docker ログを確認：`docker-compose logs -f [service]`
4. Adminer (MySQL管理UI) でデータベースを確認

---

## 次のステップ

「[Phase 1: セットアップ実装ガイド](./01-setup-implementation.md)」から開始してください。
