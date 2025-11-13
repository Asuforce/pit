import http from 'k6/http';
import { check, group, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';

export const options = {
  stages: [
    { duration: '2m', target: 100 },
    { duration: '1m', target: 1000 },  // Spike
    { duration: '5m', target: 1000 },
    { duration: '2m', target: 100 },
    { duration: '1m', target: 0 },
  ],
  thresholds: {
    'http_req_duration': ['p(99)<5000'],
    'http_req_failed': ['rate<0.15'],
  },
};

export default function () {
  group('Product List', function () {
    let res = http.get(`${BASE_URL}/api/products`);
    check(res, {
      'status is 200': (r) => r.status === 200,
    });
    sleep(0.1);
  });

  group('Product Detail', function () {
    let res = http.get(`${BASE_URL}/api/products/1`);
    check(res, {
      'status is 200': (r) => r.status === 200,
    });
    sleep(0.1);
  });
}
