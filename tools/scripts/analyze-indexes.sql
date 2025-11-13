-- MySQLインデックス分析スクリプト
-- MySQL Workbench または CLI で実行

-- テーブル情報を表示
SELECT
  TABLE_NAME,
  ENGINE,
  TABLE_ROWS,
  DATA_LENGTH / 1024 / 1024 AS 'Size(MB)',
  INDEX_LENGTH / 1024 / 1024 AS 'Index Size(MB)'
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'pit_development'
ORDER BY DATA_LENGTH DESC;

-- 未使用インデックスを特定
SELECT
  OBJECT_SCHEMA,
  OBJECT_NAME,
  INDEX_NAME
FROM performance_schema.table_io_waits_summary_by_index_usage
WHERE OBJECT_SCHEMA = 'pit_development'
  AND INDEX_NAME != 'PRIMARY'
  AND COUNT_READ = 0
  AND COUNT_WRITE = 0
ORDER BY OBJECT_NAME, INDEX_NAME;

-- インデックス効率を確認
SELECT
  OBJECT_NAME AS table_name,
  INDEX_NAME,
  COUNT_READ,
  COUNT_WRITE,
  COUNT_DELETE,
  COUNT_UPDATE
FROM performance_schema.table_io_waits_summary_by_index_usage
WHERE OBJECT_SCHEMA = 'pit_development'
  AND INDEX_NAME != 'PRIMARY'
ORDER BY COUNT_READ DESC;

-- テーブルごとのインデックス一覧
SELECT
  TABLE_NAME,
  INDEX_NAME,
  COLUMN_NAME,
  SEQ_IN_INDEX
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = 'pit_development'
ORDER BY TABLE_NAME, INDEX_NAME, SEQ_IN_INDEX;

-- インデックスサイズが大きい順
SELECT
  TABLE_NAME,
  INDEX_NAME,
  STAT_VALUE * @@innodb_page_size / 1024 / 1024 AS 'Index Size(MB)'
FROM mysql.innodb_index_stats
WHERE STAT_NAME = 'size'
  AND DATABASE_NAME = 'pit_development'
ORDER BY STAT_VALUE DESC;
