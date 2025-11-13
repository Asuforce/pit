# クイックスタートガイド

3ヶ月間のパフォーマンス改善学習を開始するための最初のステップです。

## 前提条件

- Docker & Docker Compose インストール済み
- k6 インストール済み（負荷テスト用）
- Make コマンド利用可能
- git インストール済み

## 1. 環境構築（10分）

### Step 1: Dockerイメージのビルド

```bash
make build
```

初回は3-5分かかります。

### Step 2: コンテナの起動

```bash
make up
```

以下の出力を確認：

```
pit_rails      | * Listening on tcp://0.0.0.0:3000
pit_mysql      | ready for connections
pit_redis      | # Ready to accept connections
```

### Step 3: データベース初期化

別のターミナルウィンドウで：

```bash
make db-setup
```

ビルド + マイグレーション + シードが自動実行されます。

## 2. 動作確認（5分）

ブラウザで以下にアクセス：

### Rails API
```
http://localhost:3000/
```

### MySQL管理画面（Adminer）
```
http://localhost:8080/
```

接続情報：
- Server: mysql
- User: pit_user
- Password: pit_password
- Database: pit_development

## 3. 学習開始

### Phase 1: 環境セットアップ（1週間）
`docs/01-setup.md` から開始してください。

計測ツールの使い方を学びます：
```bash
# ブラウザで Rack Mini Profiler にアクセス
http://localhost:3000/?pp=profile

# Rails ログで bullet の警告を確認
docker compose logs rails | grep Bullet
```

### よく使うコマンド

```bash
# Railsコンソール
make rails-shell

# MySQL管理画面へのアクセス
make mysql-shell

# ログの確認
make logs

# テスト実行
make smoke-test

# 詳細なコマンド一覧
make help
```

## 各Phaseの進め方

### 学習サイクル

1. **ドキュメント読了** (`docs/*.md`)
   - 理論と実装例を理解

2. **ベースライン計測** (`logs/`)
   - 改善前のパフォーマンス記録

3. **実装** (`backend/`)
   - コードを書いて改善

4. **計測と検証**
   ```bash
   make smoke-test
   make load-test
   ```

5. **改善効果確認**
   - ログを比較して改善度を確認

## トラブルシューティング

### Dockerが起動しない場合

```bash
# 全コンテナを停止・削除
make clean

# 再度起動
make build
make up
```

### DatabaseエラーでRailsが起動しない場合

```bash
# MySQL が完全に起動するまで待つ
sleep 30

# DB初期化を再実行
make db-reset
```

### ポートがすでに使用されている場合

```bash
# 使用中のポートを確認
lsof -i :3000  # Rails
lsof -i :3306  # MySQL
lsof -i :6379  # Redis

# 必要に応じてプロセスを終了
```

## 学習期間の目安

| Phase | 内容 | 期間 |
|-------|------|------|
| 1 | 環境セットアップ | 1週間 |
| 2 | N+1問題解決 | 1週間 |
| 3 | キャッシング戦略 | 1週間 |
| 4 | GraphQL最適化 | 1週間 |
| 5 | フロントエンド最適化 | 1週間 |
| 6 | DB最適化 | 1週間 |
| 7 | 負荷テスト & まとめ | 1週間 |
| | **合計** | **7週間 ≈ 1.5ヶ月** |

3ヶ月あれば、各Phaseを2回繰り返す時間があります。

## ディレクトリ構成の理解

```
pit/
├── docs/                 ← 学習ガイドをここから読む
├── backend/              ← コード実装はここ
├── tools/                ← テストツール・スクリプト
│   ├── k6/               ← 負荷テストシナリオ
│   ├── scripts/          ← 分析スクリプト
│   └── OPTIMIZATION_CHECKLIST.md
├── logs/                 ← 計測結果を保存（自動作成）
└── Makefile              ← よく使うコマンド
```

## 次のステップ

準備ができたら：

```bash
# Phase 1 のドキュメントを開く
cat docs/01-setup.md

# または

# Railsコンソールで簡単なクエリ実行
make rails-shell
# > Product.all.count
```

## 質問・トラブル時

1. **README.md** - プロジェクト全体の説明
2. **docs/*.md** - 各Phaseの詳細ガイド
3. **Makefile** - コマンドの説明
4. **tools/OPTIMIZATION_CHECKLIST.md** - 実装チェックリスト

すべてのドキュメントには具体的なコード例と実行手順が記載されています。

---

学習を楽しんでください！🚀
