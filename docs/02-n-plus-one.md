# Phase 2: N+1問題の発見と解決

## 学習目標
- N+1問題の仕組みを理解
- bulletを使った問題検出
- includes/preload/eager_loadの使い分け
- GraphQL DataLoaderパターンの基礎

## N+1問題とは

N件のデータを取得する際に、1件のクエリ＋N件のクエリ＝合計N+1件のクエリが実行される問題。

### 悪い例

```ruby
# app/controllers/products_controller.rb
def index
  @products = Product.all  # クエリ1: N件の商品を取得

  @products.each do |product|
    product.category    # クエリN: 各商品のカテゴリを個別取得
    product.reviews.count  # クエリN: 各商品のレビュー数を個別計測
  end
end
```

このコードは1 + N + Nのクエリを実行します。商品が1000件の場合、2001回のDB問い合わせが発生！

### 計測方法

#### 方法1: rack-mini-profilerで確認
```
http://localhost:3000/products?pp=profile
```
画面下部にクエリ数が表示されます。

#### 方法2: bulletの警告を確認
Railsログに以下のような警告が出ます：
```
Bullet: N+1 Query detected
  Product => [:category]
  Call stack: ...
```

#### 方法3: SQLログで確認
```
SELECT `products`.* FROM `products`;
SELECT `categories`.* FROM `categories` WHERE id = 1;
SELECT `categories`.* FROM `categories` WHERE id = 2;
...
```

## 解決方法

### 1. includes (推奨: 大多数の場合)

外部結合を使用。通常は最も効率的。

```ruby
# app/controllers/products_controller.rb
def index
  @products = Product.includes(:category, :reviews).all
end

# ビュー
<% @products.each do |product| %>
  <%= product.category.name %>  # キャッシュから取得（追加クエリなし）
  <%= product.reviews.count %>
<% end %>
```

実行されるクエリ：
```sql
SELECT `products`.* FROM `products`;
SELECT `categories`.* FROM `categories` WHERE id IN (1, 2, 3, ...);
SELECT `reviews`.* FROM `reviews` WHERE product_id IN (1, 2, 3, ...);
```

### 2. eager_load (結合が複雑な場合)

明示的なINNER JOINを使用。

```ruby
def index
  # categoryなしの商品も含める場合
  @products = Product.eager_load(:category).all
end
```

### 3. preload (キャッシュを優先したい場合)

複数クエリを発行しつつ、Rubyメモリにキャッシュ。

```ruby
def index
  @products = Product.preload(:category).all
end
```

## Rails Model設定

```ruby
# app/models/product.rb
class Product < ApplicationRecord
  belongs_to :category
  has_many :reviews

  scope :with_associations, -> { includes(:category, :reviews) }
end

# 使用時
@products = Product.with_associations
```

## GraphQL環境での対策

GraphQLでN+1問題が発生しやすい理由：

```graphql
query {
  products {
    id
    name
    category { name }      # N件の追加クエリ
    reviewCount
  }
}
```

### 対策: batch_loaderの使用

```ruby
# app/graphql/types/product_type.rb
class Types::ProductType < Types::BaseObject
  field :id, ID, null: false
  field :name, String, null: false
  field :category, Types::CategoryType, null: true

  def category
    batch_loader = Loaders::CategoryLoader.for
    batch_loader.load(object.category_id)
  end
end

# app/graphql/loaders/category_loader.rb
module Loaders
  class CategoryLoader
    include GraphQL::Batch::Loader

    def load(id)
      categories_by_id.then { |hash| hash[id] }
    end

    private

    def categories_by_id
      Category.where(id: ids).index_by(&:id)
    end
  end
end
```

## 演習課題

### 課題1: N+1問題を検出する
1. `http://localhost:3000/products` にアクセス
2. rack-mini-profilerで「Query Count」を確認
3. bulletの警告をRailsログで確認

目標: 200以上のクエリが実行されていることを確認

### 課題2: includesで改善する
1. ProductsControllerを修正してincludes(:category, :reviews)を追加
2. 再度パフォーマンス計測
3. クエリ数が5以下に削減されることを確認

### 課題3: GraphQLで同様の問題を確認・解決する
1. GraphQL Queryでカテゴリを含めて実行
2. batch_loaderで最適化

## チェックリスト

- [ ] bulletがインストールされている
- [ ] rack-mini-profilerでクエリ数が確認できる
- [ ] N+1問題を再現できている
- [ ] includes(:category)でクエリが削減される
- [ ] GraphQL batch_loaderが動作している

## パフォーマンス比較

| 方法 | クエリ数 | 実行時間 |
|------|--------|--------|
| N+1問題あり | 2001 | ~5000ms |
| includes使用 | 3 | ~100ms |
| GraphQL batch_loader | 3 | ~120ms |
