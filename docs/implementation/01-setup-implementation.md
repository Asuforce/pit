# Phase 1: セットアップ実装ガイド

## 概要

このフェーズでは、PIT プロジェクトの開発環境全体を構築します。Rails + GraphQL のバックエンドアプリケーションを Docker で実行し、パフォーマンス計測ツールを導入してベースラインメトリクスを記録します。

**目標**:
- Docker Compose で起動するRails + MySQL + Redis環境の構築
- GraphQLエンドポイントが正常に動作することを確認
- パフォーマンス計測ツール（rack-mini-profiler、bullet）の統合

---

## 前提条件

### 技術的前提
- Docker / Docker Compose がインストール済み
- 基本的なRailsの知識
- SQLの基礎知識

### ファイル構造
```
pit/
├── backend/                 # Railsアプリケーション
│   ├── app/
│   ├── db/
│   ├── config/
│   ├── Dockerfile
│   ├── docker-compose.yml
│   ├── Gemfile
│   └── Gemfile.lock
├── docs/
└── README.md
```

---

## ステップ1: Rails アプリケーションの初期化

### 1.1 Rails プロジェクト生成

API専用モード（ビュー層なし）でRailsアプリケーションを生成します。

```bash
# プロジェクトディレクトリの作成
mkdir pit
cd pit
mkdir backend
cd backend

# Rails 8.1 API モードで初期化
rails new . --api \
  --database=mysql \
  --skip-test \
  --skip-bundle
```

### 1.2 Ruby バージョンの確認

`.ruby-version` ファイルが生成されていることを確認：

```ruby
# .ruby-version
3.2.0
```

Ruby 3.2.0 以上であることを確認してください。

---

## ステップ2: Gemfile の設定

### 2.1 必要な Gem の追加

以下のGemを `Gemfile` に追加します：

```ruby
# Gemfile

source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.2.0"

gem "rails", "~> 8.0.0"
gem "mysql2", "~> 0.5"
gem "puma", "~> 6.0"

# JSON API serialization
gem "jsonapi-serializer"

# GraphQL
gem "graphql"
gem "graphql-batch"

# Caching and Performance
gem "redis", "~> 4.0"
gem "rack-mini-profiler", "~> 2.0"
gem "bullet"  # N+1問題検出

# Authentication (将来使用)
gem "jwt"

# Environment variables
gem "dotenv-rails"

# Logging
gem "lograge"

group :development, :test do
  gem "byebug", platforms: [:mri, :mingw, :x64_mingw]
  gem "rspec-rails"
  gem "factory_bot_rails"
end

group :development do
  gem "spring"
end
```

### 2.2 Gem のインストール

```bash
bundle install
```

---

## ステップ3: Docker 環境の構築

### 3.1 Dockerfile の作成

`backend/Dockerfile` を作成：

```dockerfile
FROM ruby:3.2.0

WORKDIR /app

# システムパッケージのインストール
RUN apt-get update && apt-get install -y \
  build-essential \
  curl \
  git \
  mysql-client \
  && rm -rf /var/lib/apt/lists/*

# Bundler のインストール
RUN gem install bundler -v 2.4.0

# Gemfile をコピーしてインストール
COPY Gemfile Gemfile.lock ./
RUN bundle install

# アプリケーションコードをコピー
COPY . .

# ポート 3000 を公開
EXPOSE 3000

# Rails サーバーを起動
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
```

### 3.2 docker-compose.yml の作成

プロジェクトルート（`pit/`）に `docker-compose.yml` を作成：

```yaml
version: '3.8'

services:
  mysql:
    image: mysql:8.0
    container_name: pit_mysql
    environment:
      MYSQL_ROOT_PASSWORD: root_password
      MYSQL_DATABASE: pit_development
      MYSQL_USER: pit_user
      MYSQL_PASSWORD: pit_password
      TZ: Asia/Tokyo
    ports:
      - "3306:3306"
    volumes:
      - mysql_data:/var/lib/mysql
      - ./backend/config/my.cnf:/etc/mysql/conf.d/my.cnf
    command: --default-authentication-plugin=mysql_native_password
    networks:
      - pit_network
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "root", "-proot_password"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7.0
    container_name: pit_redis
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    networks:
      - pit_network
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  web:
    build: ./backend
    container_name: pit_web
    command: bash -c "bundle exec rails db:create db:migrate db:seed && bundle exec rails server -b 0.0.0.0"
    ports:
      - "3000:3000"
    environment:
      RAILS_ENV: development
      RAILS_LOG_TO_STDOUT: "true"
      DATABASE_URL: mysql2://pit_user:pit_password@mysql:3306/pit_development
      REDIS_URL: redis://redis:6379/0
    volumes:
      - ./backend:/app
      - /app/tmp
    depends_on:
      mysql:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - pit_network

  adminer:
    image: adminer:latest
    container_name: pit_adminer
    ports:
      - "8080:8080"
    depends_on:
      - mysql
    networks:
      - pit_network

volumes:
  mysql_data:
  redis_data:

networks:
  pit_network:
    driver: bridge
```

### 3.3 MySQL 設定ファイルの作成

`backend/config/my.cnf` を作成：

```ini
[mysqld]
# パフォーマンス設定
max_connections = 100
max_allowed_packet = 64M
default_storage_engine = InnoDB

# スロークエリログ設定
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 0.5

# バッファプール設定
innodb_buffer_pool_size = 1G
innodb_log_file_size = 256M

# 文字セット設定
character_set_server = utf8mb4
collation_server = utf8mb4_unicode_ci

[mysql]
default_character_set = utf8mb4
```

---

## ステップ4: Rails の基本設定

### 4.1 データベース設定

`backend/config/database.yml` を確認：

```yaml
default: &default
  adapter: mysql2
  encoding: utf8mb4
  collation: utf8mb4_unicode_ci
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  host: <%= ENV.fetch("DB_HOST") { "localhost" } %>
  port: <%= ENV.fetch("DB_PORT") { 3306 } %>
  username: <%= ENV.fetch("DB_USER") { "root" } %>
  password: <%= ENV.fetch("DB_PASSWORD") { "" } %>

development:
  <<: *default
  database: pit_development

test:
  <<: *default
  database: pit_test

production:
  <<: *default
  database: pit_production
```

Dockerを使用する場合、環境変数で設定します：

```bash
# .env ファイルを作成
echo "DB_HOST=mysql" >> backend/.env
echo "DB_USER=pit_user" >> backend/.env
echo "DB_PASSWORD=pit_password" >> backend/.env
```

### 4.2 Redis キャッシュストア設定

`backend/config/environments/development.rb` を編集：

```ruby
Rails.application.configure do
  # キャッシュストアをRedisに設定
  config.cache_store = :redis_cache_store, {
    url: ENV.fetch("REDIS_URL") { "redis://localhost:6379/0" },
    expires_in: 1.hour
  }

  # bullet の設定（N+1問題検出）
  config.after_initialize do
    Bullet.enable = true
    Bullet.alert = true
    Bullet.rails_logger = true
    Bullet.add_footer = true
  end

  # rack-mini-profiler の設定
  config.middleware.use Rack::MiniProfiler
  Rack::MiniProfiler.config.position = 'bottom-right'
  Rack::MiniProfiler.config.start_hidden = false

  # ログレベルの設定
  config.log_level = :debug

  # その他の既存設定...
end
```

### 4.3 環境変数の設定

`backend/.env.development` ファイルを作成：

```bash
RAILS_ENV=development
RAILS_LOG_TO_STDOUT=true

# Database
DB_HOST=mysql
DB_PORT=3306
DB_USER=pit_user
DB_PASSWORD=pit_password
DB_NAME=pit_development

# Redis
REDIS_URL=redis://redis:6379/0

# GraphQL
GRAPHQL_DEBUG=true
```

---

## ステップ5: GraphQL スキーマの初期化

### 5.1 GraphQL 初期化

```bash
# GraphQL スキーマジェネレーター実行
rails generate graphql:install
```

これにより以下が生成されます：
- `app/graphql/pit_schema.rb`
- `app/graphql/types/`
- GraphQL相関の設定

### 5.2 GraphQL コントローラーの作成

`backend/app/controllers/graphql_controller.rb` を作成：

```ruby
class GraphqlController < ApplicationController
  # POST /graphql
  def execute
    variables = ensure_hash(params[:variables])
    query = params[:query]
    operation_name = params[:operationName]

    result = PitSchema.execute(
      query,
      variables: variables,
      operation_name: operation_name,
      context: graphql_context
    )

    render json: result
  rescue StandardError => e
    handle_error_in_development(e)
  end

  private

  def graphql_context
    {
      current_user: current_user
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

### 5.3 ルーティング設定

`backend/config/routes.rb` を編集：

```ruby
Rails.application.routes.draw do
  post "/graphql", to: "graphql#execute"

  # ヘルスチェック
  get "/health", to: proc { [200, {}, ["OK"]] }
end
```

---

## ステップ6: データベースモデルの作成

### 6.1 Product モデル

```bash
rails generate model Product \
  name:string \
  description:text \
  price:decimal \
  category:references \
  created_at:datetime \
  updated_at:datetime
```

`backend/app/models/product.rb`:

```ruby
class Product < ApplicationRecord
  belongs_to :category, optional: true
  has_many :reviews, dependent: :destroy

  validates :name, presence: true
  validates :price, presence: true, numericality: { greater_than: 0 }
end
```

### 6.2 Category モデル

```bash
rails generate model Category name:string
```

`backend/app/models/category.rb`:

```ruby
class Category < ApplicationRecord
  has_many :products, dependent: :destroy

  validates :name, presence: true, uniqueness: true
end
```

### 6.3 Review モデル

```bash
rails generate model Review \
  product:references \
  rating:integer \
  comment:text
```

`backend/app/models/review.rb`:

```ruby
class Review < ApplicationRecord
  belongs_to :product

  validates :rating, presence: true, inclusion: { in: 1..5 }
end
```

---

## ステップ7: マイグレーション実行

```bash
# Docker コンテナ内でマイグレーション実行
docker-compose exec web bundle exec rails db:create
docker-compose exec web bundle exec rails db:migrate
```

---

## ステップ8: シードデータの投入

`backend/db/seeds.rb` を編集：

```ruby
# 既存データの削除
Product.destroy_all
Category.destroy_all
Review.destroy_all

# カテゴリの作成
categories = [
  { name: "Electronics" },
  { name: "Books" },
  { name: "Clothing" },
  { name: "Home & Garden" }
]

created_categories = categories.map { |attrs| Category.create!(attrs) }

# 製品の作成（500個のサンプルデータ）
100.times do |i|
  category = created_categories.sample
  product = Product.create!(
    name: "Product #{i + 1}",
    description: "This is a sample product description for product #{i + 1}",
    price: rand(10..1000),
    category: category
  )

  # 各製品に複数のレビューを追加
  rand(0..10).times do |j|
    Review.create!(
      product: product,
      rating: rand(1..5),
      comment: "Sample review #{j + 1} for product #{product.name}"
    )
  end
end

puts "Seeded #{Product.count} products with #{Review.count} reviews"
```

シードデータを投入：

```bash
docker-compose exec web bundle exec rails db:seed
```

---

## ステップ9: GraphQL タイプの定義

### 9.1 Query タイプ

`backend/app/graphql/types/query_type.rb`:

```ruby
module Types
  class QueryType < Types::BaseObject
    # 全製品を取得
    field :products, [ProductType], null: false do
      argument :limit, Int, required: false, default_value: 10
      argument :offset, Int, required: false, default_value: 0
    end

    # 単一製品を取得
    field :product, ProductType, null: true do
      argument :id, ID, required: true
    end

    # 全カテゴリを取得
    field :categories, [CategoryType], null: false
  end

  def products(limit:, offset:)
    Product.limit(limit).offset(offset)
  end

  def product(id:)
    Product.find_by(id: id)
  end

  def categories
    Category.all
  end
end
```

### 9.2 Product Type

`backend/app/graphql/types/product_type.rb`:

```ruby
module Types
  class ProductType < Types::BaseObject
    field :id, ID, null: false
    field :name, String, null: false
    field :description, String, null: true
    field :price, Float, null: false
    field :category, CategoryType, null: true
    field :reviews, [ReviewType], null: true
    field :average_rating, Float, null: true
  end

  def average_rating
    object.reviews.average(:rating).to_f.round(2)
  end
end
```

### 9.3 Category Type

`backend/app/graphql/types/category_type.rb`:

```ruby
module Types
  class CategoryType < Types::BaseObject
    field :id, ID, null: false
    field :name, String, null: false
    field :products, [ProductType], null: true
  end
end
```

### 9.4 Review Type

`backend/app/graphql/types/review_type.rb`:

```ruby
module Types
  class ReviewType < Types::BaseObject
    field :id, ID, null: false
    field :rating, Int, null: false
    field :comment, String, null: true
    field :product, ProductType, null: false
  end
end
```

---

## ステップ10: Docker 環境の起動

### 10.1 コンテナの起動

```bash
cd pit
docker-compose up -d
```

初回実行時は、以下の処理が自動的に実行されます：
- データベースの作成
- マイグレーション実行
- シードデータ投入
- Railsサーバー起動

### 10.2 正常性確認

```bash
# ヘルスチェック
curl http://localhost:3000/health

# GraphQL エンドポイント確認
curl -X POST http://localhost:3000/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{products(limit:5){id name price}}"}'
```

---

## ステップ11: パフォーマンス計測ツールの確認

### 11.1 rack-mini-profiler の確認

ブラウザで以下にアクセス：
```
http://localhost:3000/mini-profiler-resources/help
```

### 11.2 bullet の確認

ログをチェック：

```bash
docker-compose logs web | grep Bullet
```

### 11.3 データベースログの確認

```bash
# スロークエリログをチェック
docker exec pit_mysql tail -f /var/log/mysql/slow.log
```

---

## ステップ12: ベースラインメトリクスの記録

GraphQL クエリでベースラインパフォーマンスを計測：

```bash
# 簡単なクエリ
curl -X POST http://localhost:3000/graphql \
  -H "Content-Type: application/json" \
  -d '{
    "query": "{
      products(limit: 10) {
        id
        name
        price
        category { name }
        reviews { rating }
      }
    }"
  }' | jq
```

以下のメトリクスを記録：

```json
{
  "phase": 1,
  "timestamp": "2024-01-15T10:00:00Z",
  "baseline_metrics": {
    "query_time_ms": [計測した結果],
    "database_queries": [計測した結果],
    "memory_usage_mb": [計測した結果]
  }
}
```

メトリクスは `docs/metrics/` ディレクトリに保存します。

---

## トラブルシューティング

### Docker コンテナが起動しない

```bash
# ログ確認
docker-compose logs web
docker-compose logs mysql

# コンテナの再構築
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

### データベース接続エラー

```bash
# MySQL の正常性確認
docker-compose logs mysql

# 手動接続テスト
docker exec pit_mysql mysql -u pit_user -p'pit_password' pit_development -e "SELECT 1;"
```

### GraphQL エンドポイント 404 エラー

- `config/routes.rb` で POST /graphql が定義されていることを確認
- Railsサーバーが起動しているか確認：`docker-compose logs web`

### Gemfile エラー

```bash
# Gemfile.lock を削除してリビルド
rm backend/Gemfile.lock
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

---

## 関連ドキュメント

- **学習ガイド**: [../01-setup.md](../01-setup.md) - Phase 1の理論的背景
- **次の実装**: [02-n-plus-one-implementation.md](./02-n-plus-one-implementation.md) - Phase 2: N+1問題の解決

---

## 次のステップ

Phase 1が完了したら、[Phase 2: N+1問題実装ガイド](./02-n-plus-one-implementation.md) に進んでください。

このフェーズでは以下が達成されました：
- ✅ Docker環境でRails + MySQL + Redisが正常に動作
- ✅ GraphQLエンドポイントが応答
- ✅ パフォーマンス計測ツール（bullet、rack-mini-profiler）が統合
- ✅ ベースラインメトリクスを記録

次のフェーズでは、このベースラインに対してN+1問題を検出し、改善する方法を学びます。
