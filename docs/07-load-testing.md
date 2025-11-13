# Phase 7: 負荷テストとボトルネック特定

## 学習目標
- k6を使った負荷テストシナリオ作成
- Smoke/Load/Stress/Spikeテストの実施
- パフォーマンスボトルネックの特定
- 改善効果の測定

## k6について

k6はGo言語で書かれた負荷テストツール。JavaScriptでテストシナリオを記述。

### インストール

```bash
# macOS
brew install k6

# Linux
apt-get install k6

# Docker
docker run -i grafana/k6 run - < script.js
```

### 基本的なテストスクリプト

```javascript
import http from 'k6/http';
import { check, group, sleep } from 'k6';

export const options = {
  vus: 10,           // Virtual Users数
  duration: '30s',   // テスト時間
};

export default function () {
  group('Product List', function () {
    let res = http.get('http://localhost:3000/api/products');
    check(res, {
      'status is 200': (r) => r.status === 200,
      'response time < 500ms': (r) => r.timings.duration < 500,
    });
    sleep(1);
  });

  group('Product Detail', function () {
    let res = http.get('http://localhost:3000/api/products/1');
    check(res, {
      'status is 200': (r) => r.status === 200,
    });
    sleep(1);
  });
}
```

## テストシナリオの種類

### 1. Smoke Test（事前確認）
アプリが基本的に動作するか確認。少数のユーザーで短時間。

```javascript
export const options = {
  vus: 1,
  duration: '5s',
  thresholds: {
    'http_req_duration': ['p(95)<500'],  // 95%が500ms以下
    'http_req_failed': ['rate<0.1'],     // 失敗率10%未満
  },
};
```

### 2. Load Test（通常負荷）
期待される本番ユーザー数での動作確認。

```javascript
export const options = {
  stages: [
    { duration: '2m', target: 100 },   // 100ユーザーまで2分かけて増加
    { duration: '5m', target: 100 },   // 100ユーザー維持5分
    { duration: '2m', target: 0 },     // 0まで2分かけて低下
  ],
  thresholds: {
    'http_req_duration': ['p(95)<1000'],
    'http_req_failed': ['rate<0.05'],
  },
};
```

### 3. Stress Test（限界確認）
アプリケーションの限界を確認。

```javascript
export const options = {
  stages: [
    { duration: '2m', target: 100 },
    { duration: '5m', target: 200 },
    { duration: '5m', target: 300 },
    { duration: '5m', target: 400 },
    { duration: '10m', target: 400 },
    { duration: '3m', target: 0 },
  ],
  thresholds: {
    'http_req_duration': ['p(99)<3000'],
  },
};
```

### 4. Spike Test（突発的なスパイク）
限界を超える負荷の急上昇に対応する確認。

```javascript
export const options = {
  stages: [
    { duration: '2m', target: 100 },
    { duration: '1m', target: 1000 },  // 急増
    { duration: '5m', target: 1000 },
    { duration: '2m', target: 100 },
    { duration: '1m', target: 0 },
  ],
  thresholds: {
    'http_req_duration': ['p(99)<5000'],
  },
};
```

## GraphQL負荷テストシナリオ

```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = 'http://localhost:3000/graphql';

const query = `
  query {
    products(first: 20) {
      id
      name
      price
      category {
        id
        name
      }
      reviews {
        id
        rating
      }
    }
  }
`;

export const options = {
  vus: 50,
  duration: '30s',
  thresholds: {
    'http_req_duration': ['p(95)<1000'],
    'http_req_failed': ['rate<0.05'],
  },
};

export default function () {
  const payload = JSON.stringify({ query });

  let res = http.post(BASE_URL, payload, {
    headers: {
      'Content-Type': 'application/json',
    },
  });

  check(res, {
    'status is 200': (r) => r.status === 200,
    'has data': (r) => r.body.includes('products'),
    'response time < 1s': (r) => r.timings.duration < 1000,
  });

  sleep(1);
}
```

## パフォーマンスメトリクス

### 主要指標

| メトリクス | 説明 | 良い値 |
|----------|------|------|
| http_req_duration | リクエスト処理時間 | p(95) < 1000ms |
| http_req_failed | 失敗率 | < 5% |
| http_reqs | 総リクエスト数 | - |
| vus_max | 最大仮想ユーザー数 | - |

### 出力例

```
data_received..................: 23 MB  32 kB/s
data_sent........................: 245 kB  347 B/s
http_req_blocked..................: avg=1.23ms   min=10µs    med=20µs    max=250ms
http_req_connecting................: avg=0.89ms   min=0s      med=0s      max=150ms
http_req_duration..................: avg=123.45ms min=12.34ms med=100.2ms max=890.5ms
  { expected_response:true }.......: avg=120ms    min=12ms    med=98ms    max=500ms
http_req_failed...................: 0.50%     ✗
http_req_receiving................: avg=12.3ms   min=1.2ms   med=10.5ms  max=50ms
http_req_sending..................: avg=2.3ms    min=0.2ms   med=2.1ms   max=20ms
http_req_tls_handshaking..........: avg=10ms     min=0s      med=0s      max=200ms
http_req_waiting..................: avg=108.8ms  min=10.1ms  med=87.2ms  max=800ms
http_reqs...........................: 5000       7.093/s
iteration_duration................: avg=1.12s    min=1.01s   med=1.10s   max=2.05s
iterations..........................: 5000       7.093/s
vus................................: 50         min=1       max=50
vus_max............................: 50         min=50      max=50
```

## 継続的な計測

### ベースライン記録

```bash
# 改善前のベースラインを記録
k6 run tools/k6/load-test.js > logs/baseline.txt

# JSON形式で出力して後で比較
k6 run tools/k6/load-test.js -o json=logs/baseline.json
```

### 改善後の比較

```bash
# 各改善フェーズ後に計測
k6 run tools/k6/load-test.js -o json=logs/after-caching.json
k6 run tools/k6/load-test.js -o json=logs/after-indexing.json
```

## 演習課題

### 課題1: Smoke Testの実行
1. `tools/k6/smoke-test.js` を作成
2. 1ユーザー、5秒間のテスト
3. 全リクエストが成功することを確認

### 課題2: Load Testの実行
1. ユーザーを段階的に100まで増加させるテスト
2. レスポンス時間 p(95) < 1000ms を目標
3. ベースライン結果を logs/baseline.json に保存

### 課題3: 改善効果の計測
1. N+1問題を修正
2. 改善後にLoad Testを再実行
3. レスポンス時間とスループットを比較

## チェックリスト

- [ ] k6がインストールされている
- [ ] Smoke Testが成功している
- [ ] Load Testでベースラインが記録されている
- [ ] Stress Testで限界を特定できている
- [ ] Spike Testで異常挙動がないか確認できている

## パフォーマンス改善の流れ

1. **ベースライン計測**
   ```
   http_req_duration p(95): 2000ms
   ```

2. **N+1問題修正**
   ```
   http_req_duration p(95): 600ms  (70%改善)
   ```

3. **キャッシング追加**
   ```
   http_req_duration p(95): 200ms  (90%改善)
   ```

4. **インデックス最適化**
   ```
   http_req_duration p(95): 100ms  (95%改善)
   ```
