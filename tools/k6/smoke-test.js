import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';

export const options = {
  vus: 1,
  duration: '5s',
  thresholds: {
    'http_req_duration': ['p(95)<500'],
    'http_req_failed': ['rate<0.1'],
  },
};

export default function () {
  // ヘルスチェック
  let res = http.get(`${BASE_URL}/`);
  check(res, {
    'status is 200': (r) => r.status === 200,
  });
  sleep(1);

  // 商品一覧
  res = http.get(`${BASE_URL}/api/products`);
  check(res, {
    'products list status is 200': (r) => r.status === 200,
    'has content': (r) => r.body.length > 0,
  });
  sleep(1);

  // 商品詳細
  res = http.get(`${BASE_URL}/api/products/1`);
  check(res, {
    'product detail status is 200': (r) => r.status === 200,
  });
}
