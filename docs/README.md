# PIT ドキュメント構成ガイド

このディレクトリには2つのドキュメントグループが存在します。

## ドキュメント構成

### グループ1: 学習ガイド（docs/ 直下）

各フェーズの **概念と理論** を学ぶためのドキュメント

| ファイル | 内容 |
|---------|------|
| `01-setup.md` | 環境構築の理論と計画 |
| `02-n-plus-one.md` | N+1問題の仕組みと対策 |
| `03-caching.md` | キャッシング戦略の理論 |
| `04-graphql-optimization.md` | GraphQL最適化の概念 |
| `05-frontend-optimization.md` | フロントエンド最適化の理論 |
| `06-database-optimization.md` | DB最適化の基礎知識 |
| `07-load-testing.md` | 負荷テストの方法論 |

**特徴**:
- 理論的な説明が中心
- パフォーマンス問題の背景を理解
- 各フェーズの学習目標を明確化
- パフォーマンス改善効果の実績を記載

**読むタイミング**: **学習フェーズ開始時**

---

### グループ2: 実装ガイド（implementation/ 配下）

各フェーズの **具体的な実装** 手順とコード例

| ファイル | 内容 |
|---------|------|
| `implementation/00-overview.md` | プロジェクト全体概要（最初に読むべき） |
| `implementation/01-setup-implementation.md` | Phase 1の詳細実装手順 |
| `implementation/02-n-plus-one-implementation.md` | Phase 2の実装コード例 |
| `implementation/03-caching-implementation.md` | Phase 3の実装方法 |
| `implementation/04-graphql-implementation.md` | Phase 4の実装手順 |
| `implementation/05-frontend-implementation.md` | Phase 5の実装コード |
| `implementation/06-database-implementation.md` | Phase 6の実装例 |
| `implementation/07-load-testing-implementation.md` | Phase 7の実装手順 |

**特徴**:
- ステップバイステップの実装手順
- 具体的なコード例
- ファイルパスと設定内容を明記
- トラブルシューティングセクション付き
- 実装チェックリスト付き

**読むタイミング**: **実装を進めるときに参照**

---

## 推奨される読み方

### パターン1: 理論から実装へ（推奨）

```
学習ガイドで概念を理解 → 実装ガイドで手を動かす
```

**例: Phase 2（N+1問題）の場合**

1. `02-n-plus-one.md` を読んで N+1 問題を理解
   - 問題の仕組み
   - なぜパフォーマンスが低下するのか
   - 解決策の種類

2. `implementation/02-n-plus-one-implementation.md` で実装
   - bullet の設定
   - includes/preload の実装
   - DataLoader の実装
   - トラブルシューティング

### パターン2: 急いでいる場合（実装重視）

```
implementation/00-overview.md → 各Phase の実装ガイド
```

理論より実装を優先する場合は、`implementation/` 配下のドキュメントのみで進められます。

---

## 各ドキュメントの関係図

```
README.md（プロジェクトルート）
  └─ docs/README.md（このファイル）
      ├─ グループ1: 学習ガイド
      │  ├─ 01-setup.md ─────────────────┐
      │  ├─ 02-n-plus-one.md ────────────┤
      │  ├─ 03-caching.md ───────────────┤
      │  ├─ 04-graphql-optimization.md ──┤
      │  ├─ 05-frontend-optimization.md ─┤
      │  ├─ 06-database-optimization.md ─┤
      │  └─ 07-load-testing.md ──────────┤
      │                                   ↓
      └─ グループ2: 実装ガイド
         ├─ implementation/00-overview.md（最初に読む）
         ├─ implementation/01-setup-implementation.md ◄─┐
         ├─ implementation/02-n-plus-one-implementation.md ◄──┤
         ├─ implementation/03-caching-implementation.md ◄──┤
         ├─ implementation/04-graphql-implementation.md ◄──┤
         ├─ implementation/05-frontend-implementation.md ◄──┤
         ├─ implementation/06-database-implementation.md ◄──┤
         └─ implementation/07-load-testing-implementation.md ◄─┘
```

---

## クイックリファレンス

### 「N+1問題について学びたい」

1. **概念を理解したい** → `02-n-plus-one.md`
2. **実装したい** → `implementation/02-n-plus-one-implementation.md`

### 「キャッシング戦略を理解したい」

1. **理論を学びたい** → `03-caching.md`
2. **Redis を設定したい** → `implementation/03-caching-implementation.md`

### 「パフォーマンステストを実施したい」

1. **テストの種類を知りたい** → `07-load-testing.md`
2. **k6 スクリプトを書きたい** → `implementation/07-load-testing-implementation.md`

---

## ドキュメントの特徴

### 学習ガイド（docs/ 直下）の特徴

✅ **理論ベース**
- なぜ最適化が必要か
- どのような問題があるか
- どのような解決方法があるか

✅ **パフォーマンス実績**
- 改善前後の比較
- 効果測定の方法

✅ **演習課題**
- 理解度チェック

### 実装ガイド（implementation/ 配下）の特徴

✅ **実行ベース**
- 何をインストールするか
- どのファイルを編集するか
- どのコマンドを実行するか

✅ **コード例**
- 実装の具体例
- ファイルパス付き

✅ **トラブルシューティング**
- よくあるエラー
- 解決方法

---

## 最初に読むべきドキュメント

### 初めての方

1. プロジェクトルートの `README.md`
2. 本ファイル（`docs/README.md`）
3. `implementation/00-overview.md`

この順序で読むことで、プロジェクト全体を理解した上で、各フェーズを段階的に進められます。

---

## フィードバック

各ドキュメントに不足している内容や、わかりやすくできる部分がありましたら、以下の方法でお知らせください：

- GitHub Issues に報告
- Pull Request で改善案を提出
- ドキュメント内のコード例が実行できない場合は即座に報告

---

## ドキュメント更新履歴

- **2024-01-15**: 実装ガイド（implementation/）の完成
- **2024-01-15**: ドキュメント構成ガイド（本ファイル）を作成
