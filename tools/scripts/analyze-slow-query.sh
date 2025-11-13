#!/bin/bash

# MySQLスロークエリログ分析スクリプト
# 使用例: bash analyze-slow-query.sh

CONTAINER_NAME="pit_mysql"
LOG_FILE="/var/log/mysql/slow.log"
OUTPUT_DIR="logs"

# ログディレクトリ作成
mkdir -p $OUTPUT_DIR

# スロークエリログをコンテナからダウンロード
echo "スロークエリログを取得中..."
docker compose cp ${CONTAINER_NAME}:${LOG_FILE} ${OUTPUT_DIR}/slow.log

# ログを解析
echo ""
echo "=== スロークエリログ解析結果 ==="
echo ""

if [ -f "${OUTPUT_DIR}/slow.log" ]; then
  echo "ログファイルサイズ:"
  du -h ${OUTPUT_DIR}/slow.log

  echo ""
  echo "遅いクエリTop 5:"
  echo ""

  grep "Query_time:" ${OUTPUT_DIR}/slow.log | \
    sed 's/Query_time: \([^ ]*\).*/\1/' | \
    sort -rn | head -5 | while read time; do
      echo "実行時間: ${time}秒"
    done

  echo ""
  echo "最頻クエリ Top 10:"
  echo ""
  grep "^SELECT\|^UPDATE\|^INSERT\|^DELETE" ${OUTPUT_DIR}/slow.log | \
    sort | uniq -c | sort -rn | head -10

else
  echo "スロークエリログが見つかりません"
fi

echo ""
echo "詳細ログ: ${OUTPUT_DIR}/slow.log"
