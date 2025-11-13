# Phase 1: 環境セットアップと初期計測

## 学習目標
- Docker環境の構築と起動
- Rails + MySQLの接続確認
- パフォーマンス計測ツールの導入（rack-mini-profiler, bullet）
- ベースラインパフォーマンスの計測

## 構成

- Rails 8.1
- MySQL 8.0
- Redis 7.0
- Adminer (MySQL Web管理ツール)

## セットアップ手順

### 0. Rails アプリケーション構築（初回のみ）

このステップは既にbackend/ディレクトリに完全なRailsアプリケーションが構築されている場合はスキップできます。

#### 0.1 Railsアプリケーション生成

```bash
cd backend
rails new . --api --database=mysql --skip-active-storage --skip-test --force
```

オプション説明:
- `--api`: REST API専用モード（HTMLビューやアセットパイプライン不要）
- `--database=mysql`: MySQLを使用
- `--skip-active-storage`: ファイルアップロード機能は不要
- `--skip-test`: minitestをスキップ（RSpectを使用）
- `--force`: 既存ファイルを上書き

#### 0.2 Gemfile調整と依存関係インストール

```bash
# 既存のGemfileをマージした状態で実行（既に更新済み）
cd backend
bundle install
```

Gemfileに含まれている主要なgem:
- **GraphQL**: graphql, graphql-batch
- **パフォーマンス監視**: rack-mini-profiler, bullet
- **キャッシング**: kaminari, rack-cors
- **データベース**: mysql2
- **認証**: bcrypt
- **テスト**: rspec-rails, factory_bot_rails

#### 0.3 GraphQL セットアップ

```bash
cd backend
bundle exec rails generate graphql:install
```

このコマンドにより以下が生成されます:
- `app/graphql/` - GraphQLスキーマと型定義
- `app/controllers/graphql_controller.rb` - GraphQLエンドポイント
- `config/routes.rb` - POST /graphql ルート追加

#### 0.4 設定ファイルの確認

以下のファイルが既に設定されています:

**config/database.yml**: Docker環境変数対応
```yaml
host: <%= ENV.fetch("DB_HOST") { "localhost" } %>
username: <%= ENV.fetch("DB_USER") { "pit_user" } %>
password: <%= ENV.fetch("DB_PASSWORD") { "pit_password" } %>
database: pit_development
```

**config/initializers/bullet.rb**: N+1問題検出ツール設定済み

**config/initializers/cors.rb**: CORS設定有効化済み

### 1. Docker環境の起動

```bash
# docker-compose.ymlがあるディレクトリで実行
docker compose up -d

# ログを確認
docker compose logs -f rails
```

正常に起動すると以下のメッセージが表示されます:
```
* Listening on http://0.0.0.0:3000
```

### 2. データベース初期化

```bash
# コンテナ内でデータベースを作成
docker compose exec pit_rails bundle exec rails db:create

# マイグレーション実行
docker compose exec pit_rails bundle exec rails db:migrate

# シードデータ投入（オプション）
docker compose exec pit_rails bundle exec rails db:seed
```

### 3. 動作確認

```
Rails: http://localhost:3000
GraphQL GraphiQL: http://localhost:3000/graphql
Adminer: http://localhost:8080
```

GraphQLエンドポイント確認:
```bash
curl -X POST http://localhost:3000/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "{ __typename }"}'
```

## ツール設定

### rack-mini-profiler

Gemfileに`gem 'rack-mini-profiler'`が既に入っています。

ブラウザで http://localhost:3000/?pp=help にアクセスすると設定が表示されます。

### bullet

N+1問題を自動検出するツール。Gemfileに`gem 'bullet'`が既に入っています。

config/initializers/bullet.rbで以下のように設定済みです：

```ruby
if defined?(Bullet)
  Bullet.enable = true
  Bullet.alert = true
  Bullet.bullet_logger = true
  Bullet.console = true
  Bullet.rails_logger = true
  Bullet.add_footer = true
end
```

ブラウザのコンソール、ログ、レスポンスフッターでN+1問題を検出・確認できます。

## 課題

このフェーズでは以下のような意図的なパフォーマンス問題が含まれています：
- N+1問題（商品一覧で関連データを何度も取得）
- 非効率なクエリ（WHERE句なしのSELECT全件）
- キャッシュなしの重い計算

これらは後続のフェーズで段階的に改善されます。

## ベースライン計測

後続フェーズでの改善効果を測定するため、以下を記録してください：

- 商品一覧読み込み時間（pp=profile）
- データベースクエリ数
- 平均応答時間

```bash
# パフォーマンス計測結果を保存
mkdir -p logs
```
