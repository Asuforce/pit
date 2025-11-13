# Phase 3: キャッシング戦略

## 学習目標
- Railsキャッシュの種類を理解
- Fragment CacheとRussian Doll Cachingの実装
- Redisを使った分散キャッシュの運用
- キャッシュの無効化タイミングの設計

## キャッシュの種類

### 1. Page Cache
ページ全体をファイルに保存。商品検索など動的なページには不向き。

```ruby
class ProductsController < ApplicationController
  caches_page :index
  cache_sweeper :product_sweeper
end
```

### 2. Action Cache
アクション全体をキャッシュ。パラメータを考慮。

```ruby
class ProductsController < ApplicationController
  caches_action :show
end
```

### 3. Fragment Cache
ページの一部をキャッシュ。最も柔軟で推奨。

```erb
<!-- app/views/products/index.html.erb -->
<% cache('products_list', expires_in: 1.hour) do %>
  <ul>
    <% @products.each do |product| %>
      <li><%= product.name %> - <%= number_to_currency(product.price) %></li>
    <% end %>
  </ul>
<% end %>
```

### 4. Russian Doll Caching
ネストされたキャッシュ。親キャッシュ無効化で子も無効化される。

```erb
<!-- app/views/products/index.html.erb -->
<% cache('products_list') do %>
  <% @products.each do |product| %>
    <% cache(product) do %>
      <div class="product">
        <h2><%= product.name %></h2>
        <p><%= number_to_currency(product.price) %></p>
      </div>
    <% end %>
  <% end %>
<% end %>
```

## Redis キャッシュストア設定

### config/environments/production.rb

```ruby
config.cache_store = :redis_cache_store, {
  url: ENV['REDIS_URL'],
  connect_timeout: 1,
  read_timeout: 1,
  write_timeout: 1,
  reconnect_attempts: 0,
}
```

### 開発環境での設定

```ruby
# config/environments/development.rb
config.cache_store = :memory_store
config.action_controller.perform_caching = true
```

## キャッシュキーの設計

```ruby
# app/models/product.rb
class Product < ApplicationRecord
  def cache_key_with_version
    "product-#{id}-#{updated_at.to_i}"
  end
end

# ビューで自動使用
<% cache(product) do %>
  <!-- product.cache_key_with_version が使用される -->
<% end %>
```

## キャッシュの無効化

### パターン1: 時間ベース無効化
```erb
<% cache('expensive_list', expires_in: 1.hour) do %>
  <!-- 1時間後に自動削除 -->
<% end %>
```

### パターン2: イベントベース無効化
```ruby
# app/models/product.rb
class Product < ApplicationRecord
  after_update :clear_cache

  private

  def clear_cache
    Rails.cache.delete("product-#{id}")
  end
end
```

### パターン3: Sweeper（古い方法）
```ruby
# app/sweepers/product_sweeper.rb
class ProductSweeper < ActionController::Caching::Sweeper
  observe Product

  def after_update(product)
    expire_cache_for(product)
  end

  private

  def expire_cache_for(product)
    expire_fragment('products_list')
  end
end
```

## GraphQLキャッシング

```ruby
# app/graphql/types/product_type.rb
class Types::ProductType < Types::BaseObject
  field :id, ID, null: false
  field :name, String, null: false
  field :reviews, [Types::ReviewType], null: true

  def reviews
    # クエリ結果をメモ化
    @reviews ||= object.reviews
  end
end
```

## パフォーマンス計測

### キャッシュヒット率の確認

```ruby
# app/controllers/products_controller.rb
def index
  cache_info = {
    cache_store: Rails.cache.class.name,
    cache_enabled: ActionController::Base.perform_caching,
  }

  render json: { cache_info: cache_info }
end
```

### Redis統計情報

```bash
docker compose exec redis redis-cli INFO stats
```

## 演習課題

### 課題1: Fragment Cacheの実装
1. 商品リストビューにfragment cacheを追加
2. キャッシュ有効期限を1時間に設定
3. 2回目のアクセスが高速化されることを確認

### 課題2: Russian Doll Caching
1. 商品リスト全体と個別商品の両方をキャッシュ化
2. 1つの商品を更新して、そのキャッシュのみ無効化
3. 他の商品はキャッシュを使用

### 課題3: Redisキャッシュ接続確認
```bash
docker compose exec rails bundle exec rails c
> Rails.cache.write('test_key', 'test_value')
> Rails.cache.read('test_key')
# => 'test_value'
```

## チェックリスト

- [ ] Redisが正常に接続されている
- [ ] Fragment cacheが実装されている
- [ ] キャッシュ無効化が自動化されている
- [ ] Redisのデータを確認できている
- [ ] キャッシュ有効化でレスポンス時間が改善している

## パフォーマンス比較

| 方法 | DB クエリ | レスポンス時間 |
|------|---------|---------------|
| キャッシュなし | 3 | ~100ms |
| Fragment cache | 0 (1回目) | ~5ms (2回目) |
| Russian Doll | 0 (update時のみ無効) | ~5ms |
