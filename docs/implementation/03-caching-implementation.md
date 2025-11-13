# Phase 3: キャッシング戦略実装ガイド

## 概要

このフェーズでは、Rails のキャッシング機能と Redis を使用した分散キャッシングを実装します。複数のキャッシング戦略（Fragment Cache、Russian Doll Caching、キャッシュ無効化）を学び、アプリケーションのパフォーマンスをさらに向上させます。

**目標**:
- Fragment Cache の実装
- Russian Doll Caching の実装
- キャッシュキー設計
- キャッシュ無効化タイミングの決定
- Redis キャッシュストアの運用

---

## 前提条件

### 完了していることを確認
- Phase 1: セットアップ完了
- Phase 2: N+1問題解決完了
- Docker 環境で Redis が起動

### 技術的前提
- Fragment Caching の基本概念
- キャッシュキー設計の理解
- データベーストランザクションの基礎

---

## パート1: Rails キャッシング機構の理解

### 1.1 Rails キャッシングの種類

Rails には複数のキャッシング戦略があります：

| キャッシュ種 | 説明 | ユースケース |
|-----------|------|-----------|
| Page Cache | ページ全体をキャッシュ | 静的なページ |
| Action Cache | アクション全体をキャッシュ | 認証なし、動的でないアクション |
| Fragment Cache | ページの一部をキャッシュ | ページの一部が動的 |
| Russian Doll Caching | ネストされた Fragment Cache | 複雑なページ構造 |
| Query Cache | クエリ結果をキャッシュ | リクエスト内での重複クエリ |

### 1.2 キャッシュストア

Django では複数のキャッシュストアが選択できます：

```ruby
# メモリストア（デフォルト）
config.cache_store = :memory_store

# ファイルストア
config.cache_store = :file_store, "tmp/cache"

# Redis ストア（推奨）
config.cache_store = :redis_cache_store, {
  url: "redis://localhost:6379/0",
  expires_in: 1.hour
}
```

---

## パート2: Redis キャッシュストア設定

### 2.1 Redis 設定確認

`backend/config/environments/development.rb`:

```ruby
Rails.application.configure do
  # Redis キャッシュストア設定
  config.cache_store = :redis_cache_store, {
    url: ENV.fetch("REDIS_URL") { "redis://localhost:6379/0" },
    expires_in: 1.hour,
    compress: true,
    # 圧縮を有効化（大きなオブジェクト向け）
    compress_threshold: 1.kilobyte
  }

  # キャッシュ有効化
  config.action_controller.perform_caching = true

  # ログに cache キーを出力
  config.log_level = :debug
end
```

### 2.2 Redis 接続確認

```bash
# Redis が起動しているか確認
docker-compose exec redis redis-cli ping
# Output: PONG

# キャッシュを確認
docker-compose exec redis redis-cli KEYS "*"
```

---

## パート3: Fragment Cache の実装

### 3.1 基本的な Fragment Cache

Fragment Cache は、キャッシュできる部分とできない部分が混在するビューで使用します。

JSON レスポンスでの Fragment Cache 例：

`backend/app/controllers/api/products_controller.rb`:

```ruby
module Api
  class ProductsController < ApplicationController
    def index
      @products = Product.includes(:category, :reviews).limit(10)

      render json: {
        products: @products.map { |product| product_as_json(product) }
      }
    end

    private

    def product_as_json(product)
      cache_key = "product:#{product.id}:json"

      Rails.cache.fetch(cache_key, expires_in: 1.hour) do
        {
          id: product.id,
          name: product.name,
          description: product.description,
          price: product.price,
          category: product.category&.slice(:id, :name),
          reviews_count: product.reviews.count
        }
      end
    end
  end
end
```

### 3.2 キャッシュキーの設計

キャッシュキーは一意で、バージョン管理が容易である必要があります：

```ruby
# 悪い例：バージョン管理が難しい
cache_key = "product_#{product.id}"

# 良い例：タイムスタンプを含める
cache_key = "product:#{product.id}:#{product.updated_at.to_i}"

# さらに良い例：Rails の cache_key_with_version を使用
cache_key = product.cache_key_with_version

# 更にカスタマイズ
cache_key = "product:#{product.id}:reviews:#{product.reviews.maximum(:updated_at)&.to_i}"
```

### 3.3 モデルでの cache_key_with_version

`backend/app/models/product.rb` を編集：

```ruby
class Product < ApplicationRecord
  belongs_to :category, optional: true
  has_many :reviews, dependent: :destroy

  validates :name, presence: true
  validates :price, presence: true, numericality: { greater_than: 0 }

  # デフォルトの cache_key を使用
  # Rails は自動的に updated_at を含める

  # または、カスタム cache_key を定義
  def cache_key_with_version
    "#{super}:category:#{category_id}:reviews:#{reviews.maximum(:updated_at)&.to_i}"
  end
end
```

---

## パート4: Russian Doll Caching

Russian Doll Caching は、ネストされたキャッシュで外側のキャッシュは内側が変更されると自動的に無効化されます。

### 4.1 ネストされたキャッシュ構造

```ruby
# 複雑なデータ構造
{
  product: {
    id: 1,
    name: "Product 1",
    category: { id: 10, name: "Electronics" },
    reviews: [
      { id: 100, rating: 5, comment: "Great!" },
      { id: 101, rating: 4, comment: "Good" }
    ]
  }
}
```

### 4.2 実装例

`backend/app/controllers/api/products_controller.rb`:

```ruby
def product_with_nested_cache(product)
  # 外側のキャッシュ（製品全体）
  Rails.cache.fetch("product:#{product.id}:detail", expires_in: 1.hour) do
    {
      id: product.id,
      name: product.name,
      price: product.price,
      category: cached_category(product.category),
      reviews: cached_reviews(product.reviews)
    }
  end
end

def cached_category(category)
  return nil if category.nil?

  # 内側のキャッシュ（カテゴリ）
  Rails.cache.fetch("category:#{category.id}:detail", expires_in: 1.hour) do
    { id: category.id, name: category.name }
  end
end

def cached_reviews(reviews)
  # 内側のキャッシュ（レビュー一覧）
  reviews.map { |review| cached_review(review) }
end

def cached_review(review)
  # 最も内側のキャッシュ（個別レビュー）
  Rails.cache.fetch("review:#{review.id}:detail", expires_in: 1.hour) do
    {
      id: review.id,
      rating: review.rating,
      comment: review.comment
    }
  end
end
```

---

## パート5: キャッシュ無効化戦略

### 5.1 コールバックによる無効化

データが更新されたときに、関連するキャッシュを無効化します。

`backend/app/models/product.rb`:

```ruby
class Product < ApplicationRecord
  belongs_to :category, optional: true
  has_many :reviews, dependent: :destroy

  after_update :invalidate_caches

  validates :name, presence: true
  validates :price, presence: true, numericality: { greater_than: 0 }

  private

  def invalidate_caches
    # 自分のキャッシュを削除
    Rails.cache.delete("product:#{id}:json")
    Rails.cache.delete("product:#{id}:detail")

    # カテゴリのキャッシュも削除（関連が変更された可能性）
    if category_id_changed?
      Rails.cache.delete("category:#{category_id}:products")
      Rails.cache.delete("category:#{category_id_before_last_save}:products") if category_id_before_last_save
    end
  end
end
```

`backend/app/models/review.rb`:

```ruby
class Review < ApplicationRecord
  belongs_to :product

  after_create :invalidate_product_cache
  after_update :invalidate_product_cache
  after_destroy :invalidate_product_cache

  validates :rating, presence: true, inclusion: { in: 1..5 }

  private

  def invalidate_product_cache
    # 関連する製品のキャッシュを削除
    Rails.cache.delete("product:#{product_id}:json")
    Rails.cache.delete("product:#{product_id}:detail")
    Rails.cache.delete("review:#{id}:detail")
  end
end
```

### 5.2 タグベースのキャッシュ無効化

Redis では、タグを使ったキャッシュ管理も可能です。

```ruby
# キャッシュにタグを付与
Rails.cache.write(
  "product:#{product.id}:json",
  product_data,
  tags: ["product", "product:#{product.id}", "category:#{product.category_id}"]
)

# タグで一括削除
Rails.cache.delete_matched_tags("product")
```

---

## パート6: GraphQL でのキャッシング

### 6.1 Field Caching

GraphQL の各フィールドをキャッシュします。

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

    # 個別フィールドのキャッシュ
    def price
      cache_key = "product:#{object.id}:price"
      Rails.cache.fetch(cache_key, expires_in: 1.hour) do
        object.price
      end
    end

    def average_rating
      cache_key = "product:#{object.id}:average_rating"
      Rails.cache.fetch(cache_key, expires_in: 1.hour) do
        object.reviews.average(:rating).to_f.round(2)
      end
    end
  end
end
```

### 6.2 クエリレベルのキャッシング

全体的なクエリ結果をキャッシュ：

`backend/app/graphql/types/query_type.rb`:

```ruby
module Types
  class QueryType < Types::BaseObject
    field :products, [ProductType], null: false do
      argument :limit, Int, required: false, default_value: 10
      argument :offset, Int, required: false, default_value: 0
    end

    def products(limit:, offset:)
      cache_key = "products:list:#{limit}:#{offset}"

      Rails.cache.fetch(cache_key, expires_in: 30.minutes) do
        Product
          .includes(:category, :reviews)
          .limit(limit)
          .offset(offset)
      end
    end
  end
end
```

---

## パート7: キャッシュパフォーマンス測定

### 7.1 キャッシュヒット率の計測

```ruby
# キャッシュ統計を取得
redis = Redis.new(url: ENV.fetch("REDIS_URL"))
info = redis.info('stats')

cache_hits = info['keyspace_hits'].to_i
cache_misses = info['keyspace_misses'].to_i
hit_rate = cache_hits.to_f / (cache_hits + cache_misses) * 100

puts "Cache Hit Rate: #{hit_rate.round(2)}%"
```

### 7.2 改善効果の計測

```bash
# キャッシュなしでテスト
curl -X POST http://localhost:3000/graphql \
  -H "Content-Type: application/json" \
  -H "Cache-Control: no-cache" \
  -d '{"query":"{products(limit:10){id name category{name} reviews{rating}}}"}'

# 同じクエリを複数回実行（キャッシュを利用）
for i in {1..5}; do
  curl -X POST http://localhost:3000/graphql ...
done
```

### 7.3 メトリクス記録

```json
{
  "phase": 3,
  "timestamp": "2024-01-15T12:00:00Z",
  "metrics": {
    "cache_hit_rate_percent": 85.5,
    "response_time_without_cache_ms": 150,
    "response_time_with_cache_ms": 5,
    "cache_memory_usage_mb": 25,
    "improvement_ratio": 30
  }
}
```

---

## パート8: キャッシュ戦略の組み合わせ

### 8.1 最適な戦略の選択

```ruby
# 静的データ（更新頻度が低い）
# → expires_in: 1.day

Rails.cache.fetch("category:#{category.id}:products", expires_in: 1.day) do
  category.products.all
end

# 準静的データ（たまに更新）
# → expires_in: 1.hour

Rails.cache.fetch("product:#{product.id}:reviews", expires_in: 1.hour) do
  product.reviews.all
end

# 動的データ（頻繁に更新）
# → expires_in: 5.minutes または キャッシュなし

Rails.cache.fetch("product:#{product.id}:inventory", expires_in: 5.minutes) do
  product.current_inventory
end
```

### 8.2 複数のキャッシング戦略を組み合わせ

```ruby
class ProductService
  def get_products_with_caching(category_id, limit = 10)
    # レベル1: クエリレベルのキャッシュ
    Rails.cache.fetch("category:#{category_id}:products:#{limit}", expires_in: 1.hour) do
      # レベル2: N+1問題の解決（includes）
      products = Category.find(category_id)
        .products
        .includes(:category, :reviews)
        .limit(limit)

      # レベル3: 個別製品のキャッシュ
      products.map { |p| product_as_json(p) }
    end
  end

  private

  def product_as_json(product)
    # 最下位レベル: 個別キャッシュ
    Rails.cache.fetch(product.cache_key_with_version, expires_in: 1.hour) do
      {
        id: product.id,
        name: product.name,
        price: product.price
      }
    end
  end
end
```

---

## パート9: キャッシュのトラブルシューティング

### 9.1 キャッシュが効かない場合

```ruby
# 1. キャッシュストアが有効か確認
Rails.cache.class  # => ActiveSupport::Cache::RedisStore

# 2. キャッシュキーが一致しているか確認
Rails.cache.fetch("test:key") { "value" }
Rails.cache.read("test:key")  # => "value"

# 3. TTL（有効期限）を確認
redis = Redis.new
redis.ttl("test:key")  # => 残り秒数
```

### 9.2 キャッシュが無効化されない

```ruby
# スタンプベースの無効化を使用
# Rails が自動的に updated_at を含める

# または手動で無効化
Rails.cache.delete("product:#{product.id}:json")

# パターンマッチで削除
Rails.cache.delete_matched("product:#{product.id}:*")
```

### 9.3 メモリ不足

```ruby
# Redis のメモリ使用量を確認
redis = Redis.new
info = redis.info('memory')
puts "Memory usage: #{info['used_memory_human']}"

# 古いキャッシュを削除
Redis.new.flushdb

# または TTL を短くする
config.cache_store = :redis_cache_store, {
  url: "redis://localhost:6379/0",
  expires_in: 30.minutes  # 1時間から短縮
}
```

---

## 関連ドキュメント

- **学習ガイド**: [../03-caching.md](../03-caching.md) - キャッシング戦略の理論
- **前の実装**: [02-n-plus-one-implementation.md](./02-n-plus-one-implementation.md) - Phase 2: N+1問題
- **次の実装**: [04-graphql-implementation.md](./04-graphql-implementation.md) - Phase 4: GraphQL最適化

---

## 実装チェックリスト

- [ ] Redis キャッシュストアが設定されている
- [ ] Fragment Cache を実装
- [ ] キャッシュキー設計が適切
- [ ] after_update コールバックでキャッシュ無効化
- [ ] Russian Doll Caching を実装
- [ ] GraphQL フィールドレベルのキャッシング
- [ ] キャッシュヒット率を計測
- [ ] パフォーマンス改善を記録

---

## 次のステップ

Phase 3が完了したら、[Phase 4: GraphQL最適化実装ガイド](./04-graphql-implementation.md) に進んでください。

このフェーズでは以下が達成されました：
- ✅ Redis キャッシュストアが設定された
- ✅ Fragment Cache が実装
- ✅ Russian Doll Caching が実装
- ✅ キャッシュ無効化戦略が確立
- ✅ キャッシュヒット率が向上（85%以上）
- ✅ 約30倍のパフォーマンス改善を確認

次のフェーズでは、GraphQL の最適化（クエリ複雑度制限、Batch Loader など）を学びます。
