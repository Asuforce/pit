.PHONY: help build up down logs rails-shell db-create db-migrate db-seed db-reset shell mysql-shell redis-cli clean benchmark load-test stress-test

help:
	@echo "パフォーマンス改善学習環境"
	@echo ""
	@echo "初期セットアップ:"
	@echo "  make build          - Dockerイメージをビルド"
	@echo "  make up             - コンテナ起動"
	@echo "  make db-setup       - DB作成・マイグレーション・シード"
	@echo ""
	@echo "開発コマンド:"
	@echo "  make rails-shell    - Railsコンソール起動"
	@echo "  make db-migrate     - DBマイグレーション実行"
	@echo "  make db-seed        - DBシード実行"
	@echo "  make db-reset       - DBリセット（マイグレーション実行なし）"
	@echo "  make logs           - コンテナログ表示（全サービス）"
	@echo ""
	@echo "データベース操作:"
	@echo "  make mysql-shell    - MySQLコンソール"
	@echo "  make redis-cli      - Redis CLI"
	@echo ""
	@echo "テスト・計測:"
	@echo "  make smoke-test     - Smoke テスト実行"
	@echo "  make load-test      - Load テスト実行"
	@echo "  make stress-test    - Stress テスト実行"
	@echo ""
	@echo "メンテナンス:"
	@echo "  make clean          - コンテナ・ボリューム削除"
	@echo "  make down           - コンテナ停止"

# === Docker コマンド ===

build:
	docker compose build

up:
	docker compose up -d
	docker compose logs -f rails

down:
	docker compose down

logs:
	docker compose logs -f

clean:
	docker compose down -v

# === Rails コマンド ===

rails-shell:
	docker compose exec rails bundle exec rails c

db-create:
	docker compose exec rails bundle exec rails db:create

db-migrate:
	docker compose exec rails bundle exec rails db:migrate

db-seed:
	docker compose exec rails bundle exec rails db:seed

db-setup: db-create db-migrate db-seed
	@echo "✓ Database setup complete"

db-reset:
	docker compose exec rails bundle exec rails db:reset

db-drop:
	docker compose exec rails bundle exec rails db:drop

# === データベース操作 ===

mysql-shell:
	docker compose exec mysql mysql -u pit_user -p pit_password pit_development

redis-cli:
	docker compose exec redis redis-cli

# === テスト・計測 ===

smoke-test:
	k6 run tools/k6/smoke-test.js

load-test:
	k6 run tools/k6/load-test.js

stress-test:
	k6 run tools/k6/stress-test.js

spike-test:
	k6 run tools/k6/spike-test.js

# === ユーティリティ ===

logs-slow-query:
	docker compose exec mysql tail -f /var/log/mysql/slow.log

explain-sample:
	@echo "Sample EXPLAIN queries:"
	docker compose exec mysql mysql -u pit_user -p pit_password pit_development -e "EXPLAIN SELECT * FROM products LIMIT 1;"

migration:
	docker compose exec rails bundle exec rails g migration $(MIGRATION_NAME)

install-gem:
	docker compose exec rails bundle add $(GEM_NAME)
