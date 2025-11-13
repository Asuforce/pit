# Phase 2: N+1問題の検出と解決ガイド

## 概要

N+1問題は、最も一般的なデータベースパフォーマンス問題です。このフェーズでは、N+1問題を理解し、検出ツール（bullet）を使用して問題を特定し、様々な解決方法（includes/preload/eager_load）を実装します。

**目標**:
- N+1問題の仕組みを理解
- bullet ツールで問題を検出
- includes、preload、eager_load を使った解決策の実装
- GraphQL DataLoaderパターンの基礎実装

---

## 前提条件

### 完了していることを確認
- Phase 1: セットアップ完了
- Docker環境で Rails + GraphQL が動作
- サンプルデータが投入済み

### 技術的前提
- Active Record クエリの基礎知識
- データベースの関連（has_many、belongs_to）の理解

---

## パート1: N+1問題の理解

### 1.1 N+1問題とは

N+1問題は以下のように発生します：

```ruby
# 1つのクエリで全製品を取得
products = Product.all  # 1回のクエリ

# 各製品のカテゴリを別々に取得
products.each do |product|
  puts product.category.name  # 各製品ごとに追加クエリが発生（Nクエリ）
end
```

この場合：
- **1回**: `SELECT * FROM products`
- **N回**: 各製品ごとに `SELECT * FROM categories WHERE id = ?`

合計 **N+1回** のクエリが発生します。

### 1.2 パフォーマンスへの影響

サンプルデータ（100製品）で計測した場合：

```
N+1問題あり:
- 101回のクエリ
- 応答時間: 500-800ms

N+1問題なし（includes使用）:
- 2回のクエリ
- 応答時間: 50-100ms

改善効果: 約5-8倍高速化
```

---

## パート2: bullet ツールを使った問題検出

### 2.1 bullet の設定確認

`backend/config/environments/development.rb` に bullet が設定されていることを確認：

```ruby
config.after_initialize do
  Bullet.enable = true
  Bullet.alert = true
  Bullet.rails_logger = true
  Bullet.add_footer = true
end
```

### 2.2 N+1問題を含むコード例

まず、意図的にN+1問題を含むコードを作成して検出を確認します。

`backend/app/controllers/api/products_controller.rb` を新規作成：

```ruby
module Api
  class ProductsController < ApplicationController
    # N+1問題を含むエンドポイント
    def index_with_n_plus_one
      @products = Product.all.limit(10)

      render json: {
        products: @products.map do |product|
          {
            id: product.id,
            name: product.name,
            category: product.category&.name,  # N+1問題: 各製品ごとにクエリ
            reviews_count: product.reviews.count  # N+1問題: 各製品ごとにクエリ
          }
        end
      }
    end

    # 改善版（includes使用）
    def index_optimized
      @products = Product.includes(:category, :reviews).limit(10)

      render json: {
        products: @products.map do |product|
          {
            id: product.id,
            name: product.name,
            category: product.category&.name,
            reviews_count: product.reviews.count
          }
        end
      }
    end
  end
end
```

ルーティングを追加：

`backend/config/routes.rb`:

```ruby
Rails.application.routes.draw do
  namespace :api do
    resources :products do
      collection do
        get :with_n_plus_one
        get :optimized
      end
    end
  end

  post "/graphql", to: "graphql#execute"
  get "/health", to: proc { [200, {}, ["OK"]] }
end
```

### 2.3 bullet の警告確認

コンテナのログを確認：

```bash
# N+1問題を含むエンドポイントにアクセス
curl http://localhost:3000/api/products/with_n_plus_one

# ログを確認
docker-compose logs web | grep -i bullet
```

bullet が以下のような警告を出力します：

```
bullet: Unused eager loading detected
  Product => [:category]
  called from ...

bullet: N+1 query detected
  Product.category association in number of objects: 10
  called from ...
```

---

## パート3: 解決策の実装

### 3.1 includes の使用

`includes` は Active Record が提供する最も一般的な N+1 問題解決方法です。

```ruby
# 悪い例
Product.all.each { |p| p.category.name }  # N+1問題

# 良い例
Product.includes(:category).each { |p| p.category.name }
```

**動作**:
1. `SELECT * FROM products`
2. `SELECT * FROM categories WHERE id IN (...)`

複数の関連を include できます：

```ruby
# 複数の関連をロード
products = Product
  .includes(:category)
  .includes(:reviews)
  .limit(10)

# または

products = Product
  .includes(:category, :reviews)
  .limit(10)

# ネストされた関連もロード可能
products = Product
  .includes(category: :related_categories)
  .includes(reviews: :author)
  .limit(10)
```

### 3.2 preload の使用

`preload` は各関連に対して個別のクエリを実行します。

```ruby
products = Product.preload(:category, :reviews).limit(10)
```

**動作**:
1. `SELECT * FROM products LIMIT 10`
2. `SELECT * FROM categories WHERE id IN (...)`
3. `SELECT * FROM reviews WHERE product_id IN (...)`

**使い分け**:
- `includes`: フィルタリングが必要な場合（JOINを使用）
- `preload`: 単純にデータをロードする場合（個別クエリ）

### 3.3 eager_load の使用

`eager_load` は LEFT OUTER JOINを使用します。

```ruby
products = Product
  .eager_load(:category, :reviews)
  .limit(10)
```

**動作**:
1つのクエリで全データを取得：
```sql
SELECT ... FROM products
LEFT OUTER JOIN categories ON ...
LEFT OUTER JOIN reviews ON ...
```

**使い分け**:
- JOINの結果をフィルタリングする必要がある場合
- 複雑なクエリの最適化に使用

### 3.4 実装例：GraphQL を使った改善

GraphQL スキーマで includes を設定：

`backend/app/graphql/types/query_type.rb` を編集：

```ruby
module Types
  class QueryType < Types::BaseObject
    field :products, [ProductType], null: false do
      argument :limit, Int, required: false, default_value: 10
      argument :offset, Int, required: false, default_value: 0
    end

    def products(limit:, offset:)
      # 関連をプリロード
      Product
        .includes(:category, :reviews)
        .limit(limit)
        .offset(offset)
    end
  end
end
```

---

## パート4: GraphQL DataLoader パターン

### 4.1 DataLoader の概念

GraphQL では、同じデータが複数のフィールドで必要になることがあります。DataLoader は複数のリクエストをバッチ化して効率化します。

例：

```graphql
{
  products {
    id
    name
    category { name }      # データベースクエリ
    reviews { rating }     # データベースクエリ
  }
}
```

複数の製品がある場合：
- 各製品ごとに category を取得 → N個のクエリ
- 各製品ごとに reviews を取得 → N個のクエリ

DataLoader を使用すると、これらを以下のようにバッチ化：
- `SELECT * FROM categories WHERE id IN (...)`
- `SELECT * FROM reviews WHERE product_id IN (...)`

### 4.2 CategoryLoader の実装

`backend/app/graphql/loaders/category_loader.rb` を新規作成：

```ruby
module Loaders
  class CategoryLoader < GraphQL::Batch::Loader
    def load(category_id)
      fetch(category_id)
    end

    private

    def cache_key(category_id)
      category_id
    end

    def perform(category_ids)
      # 指定されたIDのカテゴリをバッチロード
      categories = Category.where(id: category_ids).index_by(&:id)

      category_ids.each do |id|
        fulfill(id, categories[id])
      end
    end
  end
end
```

### 4.3 ReviewsLoader の実装

`backend/app/graphql/loaders/reviews_loader.rb` を新規作成：

```ruby
module Loaders
  class ReviewsLoader < GraphQL::Batch::Loader
    def load(product_id)
      fetch(product_id)
    end

    private

    def cache_key(product_id)
      product_id
    end

    def perform(product_ids)
      # 指定されたproduct_idのレビューをグループ化
      reviews_by_product = Review
        .where(product_id: product_ids)
        .group_by(&:product_id)

      product_ids.each do |id|
        fulfill(id, reviews_by_product[id] || [])
      end
    end
  end
end
```

### 4.4 ProductType で DataLoader を使用

`backend/app/graphql/types/product_type.rb` を編集：

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
      # DataLoader を使ってカテゴリをロード
      Loaders::CategoryLoader.for(context).load(object.category_id)
    end

    def reviews
      # DataLoader を使ってレビューをロード
      Loaders::ReviewsLoader.for(context).load(object.id)
    end

    def average_rating
      reviews.average(&:rating).to_f.round(2)
    end
  end
end
```

### 4.5 PIT Schema で GraphQL::Batch を有効化

`backend/app/graphql/pit_schema.rb`:

```ruby
class PitSchema < GraphQL::Schema
  mutation(Types::MutationType)
  query(Types::QueryType)

  # GraphQL::Batch に対応
  use GraphQL::Batch

  # その他の設定...
end
```

---

## パート5: パフォーマンス測定

### 5.1 改善前後の計測

改善前のエンドポイント：

```bash
curl http://localhost:3000/api/products/with_n_plus_one 2>&1 | head -20
```

改善後のエンドポイント：

```bash
curl http://localhost:3000/api/products/optimized 2>&1 | head -20
```

rack-mini-profiler で詳細を確認（ブラウザのコンソール出力）。

### 5.2 GraphQL クエリのプロファイリング

GraphQL クエリでN+1問題が解決されたか確認：

```bash
curl -X POST http://localhost:3000/graphql \
  -H "Content-Type: application/json" \
  -d '{
    "query": "{
      products(limit: 10) {
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
        }
      }
    }"
  }' | jq
```

### 5.3 メトリクスの記録

パフォーマンス改善を記録：

```json
{
  "phase": 2,
  "timestamp": "2024-01-15T11:00:00Z",
  "metrics": {
    "before_optimization": {
      "queries_per_request": 101,
      "response_time_ms": 650
    },
    "after_optimization": {
      "queries_per_request": 2,
      "response_time_ms": 75
    },
    "improvement_ratio": 8.67
  }
}
```

---

## パート6: テストの作成

### 6.1 Bullet テスト

`backend/spec/requests/products_spec.rb`:

```ruby
require 'rails_helper'

describe 'Products API', type: :request do
  before do
    # テストデータ作成
    @category = create(:category)
    @products = create_list(:product, 10, category: @category)
    @products.each { |p| create_list(:review, 3, product: p) }
  end

  describe 'GET /api/products/with_n_plus_one' do
    it 'detects N+1 queries with bullet' do
      expect { get '/api/products/with_n_plus_one' }.to trigger_bullet_n_plus_one_warning
    end
  end

  describe 'GET /api/products/optimized' do
    it 'does not trigger N+1 warnings' do
      expect { get '/api/products/optimized' }.not_to trigger_bullet_warning
    end
  end

  describe 'GraphQL query' do
    it 'efficiently loads products with relationships' do
      query = <<~GQL
        {
          products(limit: 10) {
            id
            name
            category { name }
            reviews { rating }
          }
        }
      GQL

      expect { post '/graphql', params: { query: query } }
        .not_to trigger_bullet_warning
    end
  end
end
```

### 6.2 テスト実行

```bash
# コンテナ内でテスト実行
docker-compose exec web bundle exec rspec spec/requests/products_spec.rb
```

---

## パート7: 他のN+1パターンと解決策

### 7.1 has_many を通じての関連

```ruby
# 悪い例
products = Product.all
products.each do |product|
  puts product.reviews.count  # N+1問題
end

# 解決策1: includes + includes
products = Product
  .includes(:reviews)
  .map { |p| [p.id, p.reviews.size] }

# 解決策2: counter_cache の使用
class Review < ApplicationRecord
  belongs_to :product, counter_cache: true
end

class CreateReviews < ActiveRecord::Migration[7.0]
  def change
    add_column :products, :reviews_count, :integer, default: 0
  end
end

# 使用
products = Product.all
products.each { |p| puts p.reviews_count }  # N+1解決
```

### 7.2 複雑な関連の最適化

```ruby
# ネストされた関連を取得
products = Product
  .includes(
    category: :parent_category,
    reviews: :author
  )
  .limit(10)

# または LEFT OUTER JOIN を使用
products = Product
  .eager_load(:category)
  .eager_load(reviews: :author)
  .limit(10)
```

---

## トラブルシューティング

### bullet が警告を出力しない

bullet の設定を確認：

```ruby
# config/environments/development.rb
config.after_initialize do
  Bullet.enable = true
  Bullet.alert = true
  Bullet.rails_logger = true
  Bullet.add_footer = true
  Bullet.bullet_logger = true  # ファイルにもログ出力
end
```

### DataLoader で NoMethodError が発生

Loader の `cache_key` メソッドが実装されているか確認：

```ruby
def cache_key(id)
  id
end
```

### includes が効かない場合

`find_by` や `where.first` の場合、includes が無視されることがあります：

```ruby
# 効かない場合
@product = Product.includes(:category).find_by(id: 1)

# 解決策
@product = Product.includes(:category).find(1)
```

---

## 関連ドキュメント

- **学習ガイド**: [../02-n-plus-one.md](../02-n-plus-one.md) - N+1問題の仕組みと対策の理論
- **前の実装**: [01-setup-implementation.md](./01-setup-implementation.md) - Phase 1: セットアップ
- **次の実装**: [03-caching-implementation.md](./03-caching-implementation.md) - Phase 3: キャッシング

---

## 実装チェックリスト

- [ ] bullet がN+1問題を検出している
- [ ] REST APIで includes を使った最適化を実装
- [ ] GraphQL で DataLoader を実装
- [ ] CategoryLoader が正常に動作
- [ ] ReviewsLoader が正常に動作
- [ ] テストでN+1警告が解決されている
- [ ] パフォーマンス改善を計測・記録

---

## 次のステップ

Phase 2が完了したら、[Phase 3: キャッシング戦略実装ガイド](./03-caching-implementation.md) に進んでください。

このフェーズでは以下が達成されました：
- ✅ N+1問題の仕組みを理解
- ✅ bullet による問題検出
- ✅ includes / preload / eager_load の実装
- ✅ GraphQL DataLoader パターンの実装
- ✅ 約5-8倍のパフォーマンス改善を確認

次のフェーズでは、Redis キャッシュを使った追加の最適化を学びます。
