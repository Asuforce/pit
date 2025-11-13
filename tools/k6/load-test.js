import http from 'k6/http';
import { check, group, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';

export const options = {
  stages: [
    { duration: '2m', target: 50 },
    { duration: '5m', target: 50 },
    { duration: '2m', target: 0 },
  ],
  thresholds: {
    'http_req_duration': ['p(95)<1000'],
    'http_req_failed': ['rate<0.05'],
  },
};

export default function () {
  group('Product List', function () {
    let res = http.get(`${BASE_URL}/api/products`);
    check(res, {
      'status is 200': (r) => r.status === 200,
      'response time < 500ms': (r) => r.timings.duration < 500,
    });
    sleep(1);
  });

  group('Product Detail', function () {
    let res = http.get(`${BASE_URL}/api/products/1`);
    check(res, {
      'status is 200': (r) => r.status === 200,
      'response time < 1000ms': (r) => r.timings.duration < 1000,
    });
    sleep(1);
  });

  group('Product Search', function () {
    let res = http.get(`${BASE_URL}/api/products?search=test`);
    check(res, {
      'status is 200': (r) => r.status === 200,
    });
    sleep(1);
  });
}
