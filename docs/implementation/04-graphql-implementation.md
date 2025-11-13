# Phase 4: GraphQL最適化実装ガイド

## 概要

このフェーズでは、GraphQL スキーマの最適化、クエリ複雑度の制限、Batch Loader の詳細実装を行います。これまでの学習（N+1問題解決、キャッシング）を基盤に、GraphQL 特有の最適化技法を習得します。

**目標**:
- GraphQL Batch Loader の詳細実装
- クエリ複雑度分析と制限
- クエリキャッシュの有効化
- GraphQL インストロスペクションの最適化

---

## 前提条件

### 完了していることを確認
- Phase 1: セットアップ完了
- Phase 2: N+1問題解決完了
- Phase 3: キャッシング戦略実装完了
- GraphQL スキーマが存在

### 技術的前提
- GraphQL スキーマ設計の理解
- Batch Loader の基本概念
- クエリ複雑度分析の理解

---

## パート1: GraphQL Batch Loader の詳細実装

### 1.1 Batch Loader の仕組み

GraphQL では、リクエスト内で複数の場所から同じデータが参照されることがあります。Batch Loader はこれらの重複リクエストを自動的に集約し、効率的にロードします。

```graphql
{
  products(limit: 3) {
    id
    name
    category { name }      # 最初のproduct -> category
    reviews {
      rating
    }
  }
}
```

このクエリでは：
- 3つの製品それぞれのカテゴリを取得（重複の可能性）
- 3つの製品それぞれのレビューを取得

Batch Loader がないと N クエリが発生し、あるとバッチクエリに集約されます。

### 1.2 CategoryLoader の詳細実装

`backend/app/graphql/loaders/category_loader.rb`:

```ruby
module Loaders
  class CategoryLoader < GraphQL::Batch::Loader
    # キャッシュキーの生成
    def cache_key(category_id)
      category_id
    end

    # バッチロード処理
    # category_ids: ロード対象のID配列
    def perform(category_ids)
      categories = Category
        .where(id: category_ids)
        .index_by(&:id)

      # 各IDについて結果を fulfill
      category_ids.each do |id|
        fulfill(id, categories[id])
      end
    end
  end
end
```

### 1.3 ProductType での使用

`backend/app/graphql/types/product_type.rb`:

```ruby
module Types
  class ProductType < Types::BaseObject
    field :id, ID, null: false
    field :name, String, null: false
    field :description, String, null: true
    field :price, Float, null: false
    field :category, CategoryType, null: true
    field :reviews, [ReviewType], null: false
    field :average_rating, Float, null: true

    def category
      # DataLoader パターンを使用
      Loaders::CategoryLoader.for(context).load(object.category_id)
    end

    def reviews
      # 複雑な場合は context 経由
      Loaders::ReviewsLoader.for(context).load(object.id)
    end

    def average_rating
      # 計算結果もキャッシュ
      cache_key = "product:#{object.id}:average_rating"
      Rails.cache.fetch(cache_key, expires_in: 1.hour) do
        reviews.average(&:rating).to_f.round(2)
      end
    end
  end
end
```

### 1.4 複数条件の Batch Loader

複雑な条件でロードする場合：

`backend/app/graphql/loaders/review_summary_loader.rb`:

```ruby
module Loaders
  class ReviewSummaryLoader < GraphQL::Batch::Loader
    # ロード対象: (product_id, min_rating) のペア
    def cache_key(args)
      "#{args[:product_id]}:#{args[:min_rating]}"
    end

    def perform(items)
      # items = [{product_id: 1, min_rating: 4}, ...]

      product_ids = items.map { |i| i[:product_id] }.uniq
      reviews = Review
        .where(product_id: product_ids)
        .index_by { |r| [r.product_id, r.rating] }

      items.each do |item|
        product_reviews = reviews.select do |key, _|
          key[0] == item[:product_id] && key[1] >= item[:min_rating]
        end.values

        fulfill(
          item,
          {
            count: product_reviews.count,
            average_rating: product_reviews.average(&:rating).to_f.round(2)
          }
        )
      end
    end
  end
end
```

---

## パート2: クエリ複雑度分析と制限

### 2.1 クエリ複雑度の概念

GraphQL クエリの複雑度は、リソース使用量を推定する指標です。

```graphql
# 複雑度: 1
{
  products(limit: 10) {
    id
  }
}

# 複雑度: より高い（フィールド数が増加）
{
  products(limit: 10) {
    id
    name
    description
    category {
      id
      name
    }
    reviews {
      id
      rating
      comment
    }
  }
}

# 複雑度: 非常に高い（ネストが深く、リスト結果が大きい）
{
  products(limit: 100) {
    id
    reviews(limit: 100) {
      id
      author {
        id
        reviews {
          id
        }
      }
    }
  }
}
```

### 2.2 PIT Schema でのクエリ複雑度制限

`backend/app/graphql/pit_schema.rb`:

```ruby
class PitSchema < GraphQL::Schema
  mutation(Types::MutationType)
  query(Types::QueryType)

  # GraphQL::Batch に対応
  use GraphQL::Batch

  # クエリ複雑度の制限
  max_query_complexity 1000
  max_query_depth 15

  # 複雑度の計算器をカスタマイズ
  query_analyzer(GraphQL::Analysis::QueryComplexity)
  query_analyzer(GraphQL::Analysis::QueryDepth)

  # リソース制限エラーハンドリング
  rescue_from(GraphQL::Analysis::MaxComplexityExceededError) do |err|
    { errors: [{ message: "Query is too complex: #{err.message}" }] }
  end

  rescue_from(GraphQL::Analysis::MaxDepthExceededError) do |err|
    { errors: [{ message: "Query depth exceeded: #{err.message}" }] }
  end
end
```

### 2.3 フィールドごとの複雑度設定

複雑度の高いフィールドに対して、より高い複雑度を割り当て：

`backend/app/graphql/types/product_type.rb`:

```ruby
module Types
  class ProductType < Types::BaseObject
    field :id, ID, null: false, complexity: 0
    field :name, String, null: false, complexity: 0
    field :price, Float, null: false, complexity: 0

    # リスト結果はより高い複雑度
    field :reviews, [ReviewType], null: false, complexity: 2

    # 計算結果も複雑度が高い
    field :average_rating, Float, null: false, complexity: 5

    # 関連データの取得は複雑度が高い
    field :category, CategoryType, null: true, complexity: 1
  end
end
```

### 2.4 複雑度の計算

クエリ実行時に複雑度が計算されます：

```ruby
# GraphQL コントローラー内
query = params[:query]
variables = params[:variables]

# 事前に複雑度を確認
result = PitSchema.execute(
  query,
  variables: variables,
  max_complexity: 1000
)

if result['errors']&.any? { |e| e['message'].include?('too complex') }
  render json: { errors: [{ message: "Query too complex" }] }, status: 422
  return
end

render json: result
```

---

## パート3: クエリキャッシュ

### 3.1 静的クエリキャッシング

静的クエリ（変数がない）をキャッシュ：

`backend/app/graphql/pit_schema.rb`:

```ruby
class PitSchema < GraphQL::Schema
  # ... 他の設定 ...

  # クエリキャッシュを有効化
  query_cache = lambda do |query_str, key, **rest|
    cache_key = "graphql:query:#{Digest::SHA256.hexdigest(query_str)}"
    cached = Rails.cache.read(cache_key)
    return cached if cached

    # キャッシュされていないければ、解析して保存
    result = GraphQL::Language::Parser.parse(query_str)
    Rails.cache.write(cache_key, result, expires_in: 1.day)
    result
  end

  # AST キャッシュ
  self.query_cache = query_cache
end
```

### 3.2 結果キャッシング

クエリの実行結果をキャッシュ：

`backend/app/controllers/graphql_controller.rb`:

```ruby
class GraphqlController < ApplicationController
  def execute
    variables = ensure_hash(params[:variables])
    query = params[:query]
    operation_name = params[:operationName]

    # 静的クエリで変数がない場合のみキャッシュ
    cache_key = if variables.empty? && operation_name.nil?
                  "graphql:result:#{Digest::SHA256.hexdigest(query)}"
                else
                  nil
                end

    # キャッシュを確認
    if cache_key && (cached_result = Rails.cache.read(cache_key))
      render json: cached_result
      return
    end

    # クエリを実行
    result = PitSchema.execute(
      query,
      variables: variables,
      operation_name: operation_name,
      context: graphql_context
    )

    # 結果をキャッシュ
    if cache_key && !result['errors']
      Rails.cache.write(cache_key, result, expires_in: 5.minutes)
    end

    render json: result
  rescue StandardError => e
    handle_error_in_development(e)
  end

  private

  def graphql_context
    {
      current_user: current_user,
      request: request
    }
  end

  def ensure_hash(ambiguous_param)
    case ambiguous_param
    when String
      JSON.parse(ambiguous_param) rescue {}
    when Hash, ActionController::Parameters
      ambiguous_param
    when nil
      {}
    else
      raise ArgumentError, "Unexpected parameter: #{ambiguous_param}"
    end
  end

  def handle_error_in_development(error)
    logger.error error.class
    logger.error error.message
    logger.error error.backtrace.join("\n")

    render json: { errors: [{ message: error.message, backtrace: error.backtrace }] }, status: 500
  end
end
```

---

## パート4: GraphQL インストロスペクション最適化

### 4.1 インストロスペクション機能

GraphQL のスキーマ自己記述機能をセキュアにする：

`backend/app/graphql/pit_schema.rb`:

```ruby
class PitSchema < GraphQL::Schema
  # ... 他の設定 ...

  # 本番環境ではインストロスペクションを無効化
  if Rails.env.production?
    disable_introspection_entry_points
  end
end
```

### 4.2 スキーム定義の最適化

不要な情報を除外：

```ruby
module Types
  class ProductType < Types::BaseObject
    field :id, ID, null: false,
      description: "Product ID"
    field :name, String, null: false,
      description: "Product name"
    field :price, Float, null: false,
      description: "Product price in USD"

    # 内部用フィールド（本番では公開しない）
    if Rails.env.development?
      field :internal_cost, Float, null: true,
        description: "[Development only] Internal cost"
    end
  end
end
```

---

## パート5: パフォーマンス最適化の検証

### 5.1 GraphQL クエリのプロファイリング

```bash
# 複雑なクエリのテスト
curl -X POST http://localhost:3000/graphql \
  -H "Content-Type: application/json" \
  -d '{
    "query": "{
      products(limit: 50) {
        id
        name
        price
        category {
          id
          name
        }
        reviews {
          id
          rating
          comment
        }
        averageRating
      }
    }"
  }' | jq
```

### 5.2 クエリ複雑度の確認

複雑度が高すぎるクエリをテスト：

```bash
curl -X POST http://localhost:3000/graphql \
  -H "Content-Type: application/json" \
  -d '{
    "query": "{
      products(limit: 1000) {
        id
        name
        category {
          id
          products(limit: 1000) {
            id
            category {
              id
              products {
                id
              }
            }
          }
        }
      }
    }"
  }' | jq
```

期待される結果：
```json
{
  "errors": [{
    "message": "Query is too complex: 1500 > 1000"
  }]
}
```

### 5.3 メトリクス記録

```json
{
  "phase": 4,
  "timestamp": "2024-01-15T13:00:00Z",
  "metrics": {
    "query_execution_time_ms": 45,
    "batch_loader_effectiveness": 0.95,
    "cache_hit_rate_percent": 78,
    "max_query_complexity": 1000,
    "improvement_over_phase3": 1.5
  }
}
```

---

## パート6: エラーハンドリングと検証

### 6.1 GraphQL エラー処理

`backend/app/graphql/pit_schema.rb`:

```ruby
class PitSchema < GraphQL::Schema
  # ... 他の設定 ...

  # 処理されないエラーをキャッチ
  rescue_from(StandardError) do |err, obj, args, ctx, field|
    if Rails.env.development?
      raise err
    else
      Rails.logger.error("GraphQL Error: #{err.message}")
      Rails.logger.error(err.backtrace.join("\n"))
      "Something went wrong"
    end
  end

  # データベースエラー
  rescue_from(ActiveRecord::RecordNotFound) do |err, obj, args, ctx, field|
    "Record not found"
  end

  # 認証エラー
  rescue_from(AuthenticationError) do |err, obj, args, ctx, field|
    "You must be logged in to access this"
  end
end
```

### 6.2 バリデーション

フィールドレベルのバリデーション：

```ruby
module Types
  class QueryType < Types::BaseObject
    field :products, [ProductType], null: false do
      argument :limit, Int, required: false, default_value: 10
      argument :offset, Int, required: false, default_value: 0

      validates :limit, numericality: { greater_than: 0, less_than_or_equal_to: 100 }
      validates :offset, numericality: { greater_than_or_equal_to: 0 }
    end

    def products(limit:, offset:)
      Product
        .includes(:category, :reviews)
        .limit(limit)
        .offset(offset)
    end
  end
end
```

---

## 関連ドキュメント

- **学習ガイド**: [../04-graphql-optimization.md](../04-graphql-optimization.md) - GraphQL最適化の概念
- **前の実装**: [03-caching-implementation.md](./03-caching-implementation.md) - Phase 3: キャッシング
- **次の実装**: [05-frontend-implementation.md](./05-frontend-implementation.md) - Phase 5: フロントエンド最適化

---

## 実装チェックリスト

- [ ] Batch Loader を実装（Category、Reviews）
- [ ] クエリ複雑度制限を設定
- [ ] max_query_depth を設定
- [ ] フィールドレベルの複雑度を定義
- [ ] クエリキャッシュを有効化
- [ ] インストロスペクション設定を確認
- [ ] エラーハンドリングを実装
- [ ] パフォーマンスメトリクスを計測

---

## 次のステップ

Phase 4が完了したら、[Phase 5: フロントエンド最適化実装ガイド](./05-frontend-implementation.md) に進んでください。

このフェーズでは以下が達成されました：
- ✅ GraphQL Batch Loader が実装
- ✅ クエリ複雑度制限が有効
- ✅ クエリキャッシュが機能
- ✅ GraphQL インストロスペクションが最適化
- ✅ エラーハンドリングが堅牢
- ✅ 約1.5倍のパフォーマンス改善を確認

次のフェーズでは、Next.js フロントエンドのパフォーマンス最適化（Core Web Vitals）を学びます。
