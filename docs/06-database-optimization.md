# Phase 6: データベース最適化

## 学習目標
- MySQLクエリの効率化
- インデックス設計とEXPLAIN分析
- InnoDB設定チューニング
- スロークエリ分析

## EXPLAINの読み方

### EXPLAIN構文

```sql
EXPLAIN SELECT * FROM products WHERE category_id = 1;
```

出力フォーマット：
```
id | select_type | table | type | possible_keys | key | key_len | ref | rows | Extra
1  | SIMPLE      | products | ref | idx_category | idx_category | 4 | const | 150 | NULL
```

### 各カラムの説明

| カラム | 意味 |
|--------|------|
| id | クエリID |
| select_type | クエリタイプ（SIMPLE, UNION, SUBQUERY等） |
| table | テーブル名 |
| type | 結合タイプ（const, eq_ref, ref, range, index, ALL） |
| key | 使用されたインデックス |
| key_len | 使用されたキーのバイト数 |
| ref | 比較対象のカラム |
| rows | スキャン対象のおおよその行数 |
| Extra | 追加情報 |

### typeの優先度（速い順）

1. **const** - 単一行マッチ（最速）
   ```sql
   SELECT * FROM products WHERE id = 1;
   ```

2. **eq_ref** - 一意インデックスでの結合
   ```sql
   SELECT * FROM products p
   JOIN categories c ON p.category_id = c.id;
   ```

3. **ref** - 非一意インデックス
   ```sql
   SELECT * FROM products WHERE category_id = 1;
   ```

4. **range** - 範囲検索
   ```sql
   SELECT * FROM products WHERE price > 100;
   ```

5. **index** - インデックス全スキャン
   ```sql
   SELECT id FROM products ORDER BY created_at;
   ```

6. **ALL** - テーブル全スキャン（最遅）
   ```sql
   SELECT * FROM products;
   ```

## インデックス設計

### 単一カラムインデックス

```sql
ALTER TABLE products ADD INDEX idx_category_id (category_id);
ALTER TABLE products ADD INDEX idx_created_at (created_at);
```

### 複合インデックス

```sql
-- WHERE category_id = ? AND price > ? のクエリに最適
ALTER TABLE products ADD INDEX idx_category_price (category_id, price);
```

クエリ：
```sql
SELECT * FROM products
WHERE category_id = 1 AND price > 100;
```

EXPLAINで確認：
```
type: ref
key: idx_category_price
rows: 45
```

### カバリングインデックス

クエリがインデックスだけで完結。テーブルアクセスなし。

```sql
-- SELECT id, category_id, price がすべてインデックスに含まれている
ALTER TABLE products ADD INDEX idx_select_cover (category_id, price, id);

-- このクエリはインデックスだけで完結（Extra: Using index）
SELECT id, category_id, price FROM products
WHERE category_id = 1 ORDER BY price;
```

### インデックス削除

```sql
ALTER TABLE products DROP INDEX idx_category_id;
```

## クエリ最適化パターン

### 悪い例（全テーブルスキャン）

```sql
SELECT * FROM products
WHERE YEAR(created_at) = 2024;  -- インデックス使用不可

-- EXPLAINで確認
-- type: ALL, rows: 50000
```

### 良い例（インデックス活用）

```sql
SELECT * FROM products
WHERE created_at >= '2024-01-01' AND created_at < '2025-01-01';

-- EXPLAINで確認
-- type: range, key: idx_created_at, rows: 5000
```

### IN句の最適化

```sql
-- 効率的
SELECT * FROM products WHERE id IN (1, 2, 3, 4, 5);

-- 大量の場合は結合を検討
SELECT p.* FROM products p
JOIN (VALUES (1), (2), (3)) AS tmp(id) ON p.id = tmp.id;
```

### JOINの最適化

```sql
-- 悪い例（小テーブルがドライビング）
SELECT * FROM categories c
LEFT JOIN products p ON c.id = p.category_id
WHERE p.price > 100;

-- 良い例（大テーブルから絞込）
SELECT * FROM products p
JOIN categories c ON p.category_id = c.id
WHERE p.price > 100;
```

## スロークエリログ分析

### ログ有効化確認

```sql
SHOW VARIABLES LIKE 'slow_query_log%';
SHOW VARIABLES LIKE 'long_query_time%';
```

### ログ位置

```bash
docker compose exec mysql tail -f /var/log/mysql/slow.log
```

### ログエントリの例

```
Query_time: 5.234567 Lock_time: 0.000123 Rows_sent: 100 Rows_examined: 50000
SELECT * FROM products WHERE category_id = 1;
```

### MySQL Utilities: pt-query-digest

```bash
# スロークエリログ分析
pt-query-digest /var/log/mysql/slow.log

# 実行サマリー
# ========================
# Profile
# ========================
# Rank Query ID Response time Count
#  1 0x1234... 5.23 100%  1
```

## InnoDB設定チューニング

### キーバッファサイズ

```ini
[mysqld]
innodb_buffer_pool_size = 1G  # 物理メモリの50-80%
innodb_log_file_size = 256M
```

### ロック戦略

```ini
[mysqld]
innodb_lock_wait_timeout = 50  # デッドロック時のタイムアウト
transaction_isolation = READ-COMMITTED  # 分離レベル
```

## 演習課題

### 課題1: EXPLAIN分析基礎
1. `SELECT * FROM products` をEXPLAIN
2. 結果で type: ALL, rows: 全行数 を確認
3. インデックスを追加してEXPLAINを再実行

```bash
docker compose exec mysql mysql -u pit_user -p pit_password pit_development
EXPLAIN SELECT * FROM products WHERE category_id = 1;
```

### 課題2: インデックス設計
1. products テーブルに複合インデックス作成
2. `SELECT * FROM products WHERE category_id = 1 AND price > 100`
3. EXPLAINで key が使用されることを確認

### 課題3: スロークエリ検出
1. 遅いクエリを実行
2. スロークエリログに記録されることを確認
3. long_query_time を 0.1 に設定して記録

```bash
docker compose exec mysql bash
tail -f /var/log/mysql/slow.log
```

## チェックリスト

- [ ] EXPLAINで typeを確認できる
- [ ] インデックスが作成されている
- [ ] クエリのtype が ref以上に改善されている
- [ ] スロークエリログが出力されている
- [ ] 複合インデックスが機能している

## パフォーマンス比較

| クエリ | インデックス | type | rows | 実行時間 |
|--------|-----------|------|------|--------|
| category_id = 1 | なし | ALL | 50000 | 100ms |
| category_id = 1 | あり | ref | 150 | 2ms |
| category_id=1 AND price>100 | 複合 | range | 45 | 1ms |
