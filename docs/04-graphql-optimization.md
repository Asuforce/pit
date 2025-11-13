# Phase 4: GraphQL最適化

## 学習目標
- GraphQLスキーマの設計と最適化
- DataLoader/batch_loaderによるN+1回避
- クエリ複雑度分析と制限
- GraphQL Fragmentの活用

## GraphQL基本設定

### Gemfileに追加

```ruby
gem 'graphql', '~> 2.0'
gem 'graphql-batch', '~> 0.5'
```

### スキーマファイルの作成

```ruby
# app/graphql/pit_schema.rb
class PitSchema < GraphQL::Schema
  mutation(Types::MutationType)
  query(Types::QueryType)

  use GraphQL::Batch::Loader
end

# config/routes.rb
post "/graphql", to: "graphql#execute"
```

## DataLoaderパターン

GraphQLで複数のクエリから参照される場合、batch_loaderを使用。

### 悪い例（N+1発生）

```ruby
# app/graphql/types/product_type.rb
class Types::ProductType < Types::BaseObject
  field :id, ID, null: false
  field :name, String, null: false
  field :category, Types::CategoryType, null: true

  def category
    # 各productごとにカテゴリを個別取得
    object.category
  end
end
```

クエリ：
```graphql
query {
  products {
    id
    name
    category { id name }  # N件の追加クエリ
  }
}
```

### 良い例（batch_loaderで最適化）

```ruby
# app/graphql/loaders/category_loader.rb
module Loaders
  class CategoryLoader
    include GraphQL::Batch::Loader

    def load(id)
      # idをリストアップして一度に取得
      categories_by_id.then { |hash| hash[id] }
    end

    private

    def categories_by_id
      Category.where(id: ids).index_by(&:id)
    end
  end
end

# app/graphql/types/product_type.rb
class Types::ProductType < Types::BaseObject
  field :id, ID, null: false
  field :name, String, null: false
  field :category, Types::CategoryType, null: true

  def category
    Loaders::CategoryLoader.for.load(object.category_id)
  end
end
```

実行されるクエリ：
```sql
SELECT * FROM categories WHERE id IN (1, 2, 3, ...);
```

## graphql-batchの詳細設定

```ruby
# app/graphql/loaders/review_loader.rb
module Loaders
  class ReviewLoader
    include GraphQL::Batch::Loader

    def load(product_id)
      reviews_by_product_id.then { |hash| hash[product_id] || [] }
    end

    private

    def reviews_by_product_id
      Review.where(product_id: ids).group_by(&:product_id)
    end
  end
end

# app/graphql/types/product_type.rb
class Types::ProductType < Types::BaseObject
  field :reviews, [Types::ReviewType], null: true

  def reviews
    Loaders::ReviewLoader.for.load(object.id)
  end
end
```

## クエリ複雑度分析

過度に複雑なクエリから守るため、複雑度スコアリング：

```ruby
# app/graphql/pit_schema.rb
class PitSchema < GraphQL::Schema
  query(Types::QueryType)

  use GraphQL::Batch::Loader

  # クエリ複雑度制限
  query_analyzer GraphQL::Analysis::QueryComplexity
  max_query_complexity 50
  max_query_depth 7
end
```

## Fragment活用

```graphql
fragment productFields on Product {
  id
  name
  price
  category {
    id
    name
  }
}

query {
  products {
    ...productFields
  }
}
```

## キャッシュ戦略

### クエリキャッシュ

```ruby
# app/graphql/pit_schema.rb
class PitSchema < GraphQL::Schema
  enable_query_caching_for_production

  def self.id_from_object(object, type_definition, execution_context)
    "#{type_definition.name}-#{object.id}"
  end
end
```

### Fragmentキャッシュ

```ruby
# app/graphql/types/product_type.rb
class Types::ProductType < Types::BaseObject
  field :reviews_count, Int, null: false

  def reviews_count
    # 計算結果をメモ化
    @reviews_count ||= object.reviews.count
  end
end
```

## パフォーマンス計測

### GraphQL Profilerの使用

```ruby
# app/controllers/graphql_controller.rb
class GraphqlController < ApplicationController
  def execute
    context = {
      current_user: current_user,
    }

    result = PitSchema.execute(
      params[:query],
      variables: params[:variables],
      operation_name: params[:operationName],
      context: context,
    )

    render json: result
  rescue StandardError => e
    raise e unless Rails.env.development?
    render json: { errors: [{ message: e.message }] }, status: 500
  end
end
```

## 演習課題

### 課題1: batch_loaderの実装
1. CategoryLoaderを実装
2. GraphQL QueryでProductとCategoryを取得
3. クエリ数がN+1から2に削減されることを確認

```graphql
query {
  products {
    id
    name
    category { id name }
  }
}
```

### 課題2: ReviewLoaderの実装
1. 各商品のレビュー一覧を取得するReviewLoaderを実装
2. batch_loaderで複数商品のレビューを一度に取得

```graphql
query {
  products {
    id
    reviews { id title rating }
  }
}
```

### 課題3: クエリ複雑度制限
1. max_query_complexityを50に設定
2. 複雑すぎるクエリをテスト

```graphql
query {
  products {
    id
    category { products { category { products { ... } } } }
  }
}
```

## チェックリスト

- [ ] GraphQL スキーマが定義されている
- [ ] batch_loaderが導入されている
- [ ] CategoryLoaderが実装されている
- [ ] クエリ複雑度制限が機能している
- [ ] N+1問題が解決されている

## パフォーマンス比較

| 方法 | クエリ数 | 実行時間 |
|------|--------|--------|
| N+1問題あり | 1001 | ~1000ms |
| batch_loader使用 | 2 | ~50ms |
