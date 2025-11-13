# Phase 6: データベース最適化実装ガイド

## 概要

このフェーズでは、MySQL クエリの効率化とインデックス設計を学びます。EXPLAIN コマンドを使用した分析、インデックス戦略、InnoDB 設定のチューニング、スロークエリ分析などを実装します。

**目標**:
- EXPLAIN コマンドを使用したクエリ分析
- インデックス設計（単一カラム、複合、カバリング）
- InnoDB パフォーマンスチューニング
- スロークエリログの分析と最適化

---

## 前提条件

### 完了していることを確認
- Phase 1-5: 全てのフェーズ実装完了
- MySQL が Docker で正常に動作
- サンプルデータが投入済み

### 技術的前提
- SQL クエリの基礎知識
- EXPLAIN 出力の読み方
- インデックスの仕組みの理解

---

## パート1: EXPLAIN コマンドの使用方法

### 1.1 EXPLAIN の基本

EXPLAIN コマンドはクエリの実行計画を表示します。

```bash
# MySQL クライアントで接続
docker exec -it pit_mysql mysql -u pit_user -p'pit_password' pit_development

# EXPLAIN を実行
EXPLAIN SELECT * FROM products WHERE id = 1\G
```

### 1.2 EXPLAIN の出力を読む

```
*************************** 1. row ***************************
           id: 1
  select_type: SIMPLE
        table: products
   partitions: NULL
         type: const        # 実行タイプ
possible_keys: PRIMARY      # 使用可能なインデックス
          key: PRIMARY      # 実際に使用されるインデックス
      key_len: 8            # インデックスキー長
          ref: const        # インデックスとの比較
         rows: 1            # 検査される行数
     filtered: 100.00
        Extra: NULL
```

**重要な列**:

| 列 | 説明 |
|----|------|
| `type` | アクセス方法（const、ref、range、scan）|
| `key` | 使用されるインデックス名 |
| `rows` | 検査される行の推定数 |
| `Extra` | 追加情報（Using index など） |

### 1.3 実行タイプの解釈

```
const       → 最速（WHERE で PRIMARY KEY）
eq_ref      → JOIN でプライマリキーをマッチ
ref         → インデックスで複数行をマッチ
range       → インデックスで範囲をマッチ
index       → インデックス全体をスキャン
ALL         → テーブル全体をスキャン（最遅）
```

### 1.4 効率的なクエリの例

**非効率なクエリ**:

```sql
EXPLAIN SELECT * FROM products WHERE created_at > '2024-01-01'\G
```

出力:
```
type: ALL
rows: 10000
key: NULL
```

**最適化後のクエリ**:

```sql
-- created_at にインデックスを作成した後
EXPLAIN SELECT * FROM products WHERE created_at > '2024-01-01'\G
```

出力:
```
type: range
rows: 100
key: idx_created_at
```

---

## パート2: インデックス設計と実装

### 2.1 単一カラムインデックス

`backend/db/migrate/xxxxx_add_indexes.rb`:

```ruby
class AddIndexes < ActiveRecord::Migration[7.0]
  def change
    # 単一カラムインデックス
    add_index :products, :name, algorithm: :inplace
    add_index :products, :category_id, algorithm: :inplace
    add_index :products, :created_at, algorithm: :inplace
    add_index :products, :updated_at, algorithm: :inplace

    add_index :categories, :name, unique: true, algorithm: :inplace

    add_index :reviews, :product_id, algorithm: :inplace
    add_index :reviews, :rating, algorithm: :inplace
    add_index :reviews, :created_at, algorithm: :inplace
  end
end
```

マイグレーション実行:

```bash
docker-compose exec web bundle exec rails db:migrate
```

### 2.2 複合インデックス

WHERE 句で複数カラムを使用する場合：

```ruby
class AddCompositeIndexes < ActiveRecord::Migration[7.0]
  def change
    # WHERE category_id = ? AND created_at > ?
    add_index :products, [:category_id, :created_at], algorithm: :inplace

    # WHERE rating >= ? AND created_at > ?
    add_index :reviews, [:rating, :created_at], algorithm: :inplace

    # WHERE product_id = ? AND rating >= ?
    add_index :reviews, [:product_id, :rating], algorithm: :inplace
  end
end
```

**複合インデックスの作成順序**:

1. WHERE 句の条件（左から右）
2. JOIN の条件
3. ORDER BY の条件

例:

```sql
SELECT * FROM products
WHERE category_id = 1 AND price > 100
ORDER BY created_at DESC;

-- インデックス: (category_id, price, created_at)
```

### 2.3 カバリングインデックス

SELECT 句のカラムを全てカバーするインデックス：

```ruby
class AddCoveringIndexes < ActiveRecord::Migration[7.0]
  def change
    # product_id, rating, comment を全て含むインデックス
    add_index :reviews,
              [:product_id, :rating],
              include: [:comment],
              name: 'idx_reviews_product_with_comment'

    # category_id, name, price, created_at を全て含むインデックス
    add_index :products,
              [:category_id, :created_at],
              include: [:name, :price],
              name: 'idx_products_category_with_details'
  end
end
```

カバリングインデックスの効果:

```
通常のインデックス:
1. インデックスから合致する行のポインタを取得
2. ポインタからテーブルにアクセス（ランダムアクセス）

カバリングインデックス:
1. インデックスから全データを取得（シーケンシャルアクセス）
→ テーブルアクセス不要
```

### 2.4 インデックスの効果確認

最適化前後の比較：

```bash
# インデックス追加前
EXPLAIN SELECT id, name, price FROM products
WHERE category_id = 1 AND created_at > '2024-01-01'\G

# インデックス追加後
EXPLAIN SELECT id, name, price FROM products
WHERE category_id = 1 AND created_at > '2024-01-01'\G
```

期待される改善：
- `rows`: 10000 → 50
- `type`: ALL → range
- `key`: NULL → idx_category_created_at

---

## パート3: クエリの最適化

### 3.1 関数を使用しない

インデックスが使用されない場合：

```sql
-- 悪い例：YEAR 関数を使用（インデックスが使用されない）
SELECT * FROM products WHERE YEAR(created_at) = 2024;

-- 良い例：DATE_TRUNC または BETWEEN を使用
SELECT * FROM products
WHERE created_at >= '2024-01-01' AND created_at < '2025-01-01';
```

### 3.2 JOIN の最適化

JOIN 順序を最適化：

```sql
-- 悪い例：絞り込みが少ない側から開始
SELECT p.* FROM products p
LEFT JOIN categories c ON p.category_id = c.id
WHERE c.name = 'Electronics';  -- ここで絞り込み

-- 良い例：絞り込みを先に実行
SELECT p.* FROM products p
INNER JOIN categories c ON p.category_id = c.id
WHERE c.name = 'Electronics';  -- INNER JOIN で絞り込み
```

### 3.3 GROUP BY の最適化

```sql
-- 悪い例：全製品を読み込んでから GROUP BY
SELECT category_id, COUNT(*) as count
FROM products
WHERE created_at > '2024-01-01'
GROUP BY category_id;

-- 良い例：インデックスを活用
-- (category_id, created_at) の複合インデックスがあると効率的
SELECT category_id, COUNT(*) as count
FROM products
WHERE created_at > '2024-01-01'
GROUP BY category_id;
```

### 3.4 LIMIT の活用

```sql
-- 悪い例：全テーブルをスキャン
SELECT * FROM reviews
ORDER BY rating DESC
LIMIT 10;

-- 良い例：インデックスを活用
-- (rating DESC, created_at DESC) インデックスが効果的
SELECT * FROM reviews
ORDER BY rating DESC, created_at DESC
LIMIT 10;
```

---

## パート4: Rails でのクエリ最適化

### 4.1 select で必要なカラムのみ取得

```ruby
# 悪い例：全カラムを取得
Product.where(category_id: 1).map(&:name)

# 良い例：必要なカラムのみ
Product.select(:id, :name)
  .where(category_id: 1)
  .map(&:name)
```

### 4.2 JOIN の活用

```ruby
# 悪い例：サブクエリで N+1 問題
products = Product.all
reviews = reviews.select { |p| p.reviews.count > 0 }

# 良い例：JOIN で効率化
Product.joins(:reviews)
  .select('products.*, COUNT(reviews.id) as review_count')
  .group('products.id')
  .having('COUNT(reviews.id) > 0')
```

### 4.3 exists? の活用

```ruby
# 悪い例：全レビューを読み込んで count
if product.reviews.count > 0
  # ...
end

# 良い例：exists? で効率化
if product.reviews.exists?
  # ...
end
```

---

## パート5: スロークエリログの分析

### 5.1 スロークエリログの有効化

Docker Compose での MySQL 設定：

`backend/config/my.cnf`:

```ini
[mysqld]
# スロークエリログ有効化
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 0.5  # 0.5秒以上のクエリを記録
log_queries_not_using_indexes = 1  # インデックスを使用しないクエリも記録
```

### 5.2 スロークエリログの確認

```bash
# ログファイルを確認
docker exec pit_mysql tail -f /var/log/mysql/slow.log

# または

docker-compose logs mysql | grep "Query_time"
```

### 5.3 mysqldumpslow での分析

```bash
# スロークエリログを分析
docker exec pit_mysql mysqldumpslow /var/log/mysql/slow.log

# Top 10 最遅クエリ
docker exec pit_mysql mysqldumpslow -t 10 /var/log/mysql/slow.log

# 実行回数が多いクエリ
docker exec pit_mysql mysqldumpslow -s c -t 10 /var/log/mysql/slow.log
```

出力例：

```
Count: 150  Time=1.25s (187s)  Lock=0.00s (0s)  Rows=10.0 (1500)
SELECT * FROM products WHERE category_id = N;

Count: 80   Time=0.85s (68s)   Lock=0.00s (0s)  Rows=100.0 (8000)
SELECT * FROM reviews WHERE product_id = N;
```

---

## パート6: InnoDB チューニング

### 6.1 バッファプール設定

`backend/config/my.cnf`:

```ini
[mysqld]
# バッファプール（ヒープメモリの 50-80%）
innodb_buffer_pool_size = 1G

# バッファプール読み込みを高速化
innodb_buffer_pool_load_at_startup = 1
innodb_buffer_pool_dump_at_shutdown = 1

# ログファイルサイズ
innodb_log_file_size = 256M

# ログバッファサイズ
innodb_log_buffer_size = 16M
```

### 6.2 スレッド設定

```ini
[mysqld]
# 同時接続スレッド数
innodb_thread_concurrency = 4

# I/O スレッド数
innodb_read_io_threads = 4
innodb_write_io_threads = 4
```

### 6.3 パフォーマンス統計

```sql
-- InnoDB パフォーマンス統計を確認
SHOW ENGINE INNODB STATUS\G

-- バッファプール使用率を確認
SELECT
  CONCAT(ROUND(100.0 * Innodb_buffer_pool_read_requests /
    (Innodb_buffer_pool_read_requests + Innodb_buffer_pool_reads), 2), '%')
  AS buffer_hit_ratio;
```

---

## パート7: パフォーマンス計測

### 7.1 クエリパフォーマンスの記録

```ruby
# config/initializers/query_logger.rb
if Rails.env.production?
  Rails.application.config.active_record.query_log_tags = {
    request_id: -> { RequestStore.store[:request_id] },
    user_id: -> { RequestStore.store[:current_user_id] }
  }
end
```

### 7.2 メトリクス収集

```bash
# Percona Monitoring and Management (PMM) でモニタリング
# または自作スクリプト

mysql -u pit_user -p'pit_password' pit_development <<EOF
SELECT
  OBJECT_SCHEMA,
  OBJECT_NAME,
  COUNT_STAR,
  AVG_TIMER_WAIT / 1000000000000 as avg_time_sec
FROM performance_schema.table_io_waits_summary_by_table
ORDER BY AVG_TIMER_WAIT DESC
LIMIT 10;
EOF
```

### 7.3 メトリクス記録

```json
{
  "phase": 6,
  "timestamp": "2024-01-15T15:00:00Z",
  "metrics": {
    "average_query_time_ms": 25,
    "slow_query_count": 5,
    "table_scan_count": 0,
    "index_usage_ratio": 0.98,
    "buffer_pool_hit_ratio": 0.99,
    "improvement_over_phase5": 3.5
  }
}
```

---

## パート8: インデックス戦略チェックリスト

### 8.1 インデックス設計のベストプラクティス

| チェック項目 | 説明 |
|-----------|------|
| 単一性 | 高いユニーク性を持つカラムを優先 |
| 選択性 | 絞り込み効率が高いカラムを優先 |
| 複合性 | WHERE → JOIN → ORDER BY の順序 |
| サイズ | インデックスサイズを最小化 |
| メンテナンス | 不要なインデックスを定期的に削除 |

### 8.2 不要なインデックスの削除

```sql
-- 使用されていないインデックスを検出
SELECT OBJECT_SCHEMA, OBJECT_NAME
FROM performance_schema.table_io_waits_summary_by_index_usage
WHERE COUNT_STAR = 0 AND OBJECT_NAME != 'PRIMARY';

-- 不要なインデックスを削除
ALTER TABLE products DROP INDEX idx_name;
```

---

## 関連ドキュメント

- **学習ガイド**: [../06-database-optimization.md](../06-database-optimization.md) - DB最適化の基礎知識
- **前の実装**: [05-frontend-implementation.md](./05-frontend-implementation.md) - Phase 5: フロントエンド最適化
- **次の実装**: [07-load-testing-implementation.md](./07-load-testing-implementation.md) - Phase 7: 負荷テスト

---

## 実装チェックリスト

- [ ] EXPLAIN コマンドでクエリ分析可能
- [ ] 単一カラムインデックスを実装
- [ ] 複合インデックスを実装
- [ ] カバリングインデックスを実装
- [ ] Rails で select を使用した最適化
- [ ] スロークエリログが有効
- [ ] InnoDB 設定をチューニング
- [ ] パフォーマンスメトリクスを計測

---

## 次のステップ

Phase 6が完了したら、[Phase 7: 負荷テスト実装ガイド](./07-load-testing-implementation.md) に進んでください。

このフェーズでは以下が達成されました：
- ✅ EXPLAIN でクエリ分析可能
- ✅ インデックス戦略が実装
- ✅ クエリが最適化
- ✅ スロークエリログを分析
- ✅ InnoDB がチューニング
- ✅ 約3.5倍のパフォーマンス改善を確認

次のフェーズでは、全ての最適化の効果を負荷テストで検証します。
