// docker run -i grafana/k6 run - < load-test.js

import http from 'k6/http';
import { sleep } from 'k6';

export let options = {
    stages: [
        { duration: '30s', target: 10 },  // 점진적 증가
        { duration: '30s', target: 30 },
        { duration: '30s', target: 50 },
        { duration: '30s', target: 0 },   // 종료
    ],
};

export default function () {
    // 웹 서버 페이지 접속
    http.get('https://web.playus.o-r.kr');

    // API 서버 엔드포인트 호출
    http.get('https://api.playus.o-r.kr/user/user/profile');

    sleep(1); // 너무 빠르게 연속 호출되지 않도록
}
