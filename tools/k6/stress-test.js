import http from 'k6/http';
import { check, group, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';

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
    'http_req_failed': ['rate<0.10'],
  },
};

export default function () {
  group('Product Operations', function () {
    // 商品一覧取得
    let res = http.get(`${BASE_URL}/api/products`);
    check(res, {
      'list status is 200': (r) => r.status === 200,
    });

    // 商品詳細取得
    res = http.get(`${BASE_URL}/api/products/1`);
    check(res, {
      'detail status is 200': (r) => r.status === 200,
    });

    // 検索
    res = http.get(`${BASE_URL}/api/products?search=test&page=1`);
    check(res, {
      'search status is 200': (r) => r.status === 200,
    });

    sleep(0.5);
  });
}
