# Sample_Performance_LoadRunner_ONEStore

> 포트폴리오 **04. 성능 병목 분석** 참고 자료

> ⚠️ **본 프로젝트는 포트폴리오용으로 제작된 샘플입니다.**
>
> 실무에서 진행한 서버 API 성능(부하) 테스트 작업을 바탕으로 재구성했으며,
> 보안 및 개인정보 보호를 위해 서버 IP, 도메인, 로그인 계정/비밀번호, 서버명 등
> 민감한 정보는 모두 제거하거나 임의의 값(`xxx`, `xxx.xxx.xxx.xxx` 등)으로 대체했습니다.
> 따라서 이 저장소의 스크립트는 실제 서버에 연결되어 동작하지 않습니다.

## 개요

앱 마켓 서비스의 서버 API를 대상으로 **LoadRunner**를 이용해 성능(부하) 테스트를 수행하고,
APM / 서버 모니터링 도구와 함께 결과를 분석해 **목표 TPS 충족 여부와 병목 구간**을 확인한 프로젝트입니다.

- VuGen으로 API 호출 시나리오(트랜잭션) 스크립트 작성 및 응답 검증 로직 추가
- Controller로 부하발생기(Load Generator)를 제어하며 단계적으로 가상 사용자(Vuser) 부하 증가
- SiteScope로 부하 구간의 서버 CPU / 메모리를 함께 수집
- Analysis로 TPS, 응답 시간, Hits/sec 등 결과 분석 후 리포트 작성

## 기술 스택

| 구분 | 사용 도구 |
|---|---|
| 성능 테스트 | LoadRunner (VuGen / Controller / Analysis) |
| 스크립트 | C (LoadRunner Web - HTTP/HTML 프로토콜) |
| 서버 모니터링 | SiteScope, PinPoint, JENNIFER, Grafana |
| 서버 접속 | SecureCRT (VBScript 로그인 스크립트) |

## 프로젝트 구조

```
Sample_Performance_LoadRunner_ONEStore/
├── README.md
└── scripts/
    └── securecrt_login.vbs   # 모니터링 대상 서버 접속용 SecureCRT 로그인 스크립트 (IP/계정 익명화)
```

## LoadRunner 구성도

<img width="1303" height="649" alt="LoadRunner 구성도" src="https://github.com/user-attachments/assets/8ae702e3-7f7d-471f-a172-8e00e57fc19a" />

LoadRunner의 각 구성 요소가 맡는 역할은 다음과 같습니다.

| 구성 요소 | 역할 |
|---|---|
| **VuGen** | 사용자 행위(API 호출)를 스크립트로 작성 |
| **Controller (부하제어기)** | 시나리오 설정, 부하발생기 제어, 실시간 모니터링 |
| **Load Generator (부하발생기)** | Controller의 지시에 따라 가상 사용자(Vuser)를 실행해 부하 발생 |
| **L4 Switch → 서버존** | 실제 서비스와 동일하게 L4를 거쳐 분산된 서버로 부하 전달 |
| **SiteScope (모니터링 툴)** | 부하 구간의 서버 CPU / 메모리 등 리소스 수집 |
| **Analysis** | 수행 결과 분석 및 그래프 / 리포트 생성 |

## 테스트 진행

### 1. 스크립트 작성 (VuGen)

<img width="562" height="368" alt="VuGen Scripts" src="https://github.com/user-attachments/assets/5ad7786e-1a02-4394-bdaf-55fbd49d8f48" />

API 하나를 하나의 **트랜잭션**(`lr_start_transaction` ~ `lr_end_transaction`)으로 묶어 응답 시간과 TPS를 API 단위로 측정했습니다.

- `web_add_header`: 실제 단말과 동일한 User-Agent, Content-Type, 네트워크 정보 헤더 추가
- `web_reg_find` / `web_reg_save_param`: 응답 Body에서 정상 응답 여부와 `errorCode`, `message`를 미리 등록해 추출
- `web_custom_request`: 파라미터화한 서버 주소와 요청 값으로 API 호출
- 정상 응답이 아니면 `LR_FAIL`로 트랜잭션을 실패 처리하고 에러 코드와 메시지를 로그로 남겨, **HTTP 200이지만 실제로는 실패한 응답**도 걸러냈습니다.

```c
Action()
{
    lr_start_transaction("05_상세");

    web_add_header("Content-Type", "application/x-www-form-urlencoded; charset=utf-8");

    // 응답 검증용 값 등록 (정상 응답 여부 / 에러 코드 / 에러 메시지)
    web_reg_find("Search=Body", "SaveCount=cnt", "Text=<action base=\"http://xxx.example.com/xxx\"", LAST);
    web_reg_save_param("errorCode", "LB=<action base=\"http://xxx.example.com/xxx\" identifier=\"", "RB=\">", LAST);
    web_reg_save_param("message", "LB=<description>", "RB=</description>", "NotFound=WARNING", LAST);

    web_custom_request("web_custom_request",
        "URL=http://xxx.example.com/xxx",
        "Method=GET",
        LAST);

    // 에러 응답이 없으면 PASS, 있으면 에러 코드/메시지를 남기고 FAIL
    if (strcmp(lr_eval_string("{cnt}"), "0") == 0)
        lr_end_transaction("05_상세", LR_PASS);
    else
    {
        lr_convert_string_encoding(lr_eval_string("{message}"), LR_ENC_UTF8, LR_ENC_SYSTEM_LOCALE, "UTF8");
        lr_error_message("05_errorCode : %s, msg : %s", lr_eval_string("{errorCode}"), lr_eval_string("{UTF8}"));
        lr_end_transaction("05_상세", LR_FAIL);
    }

    return 0;
}
```

### 2. 부하 제어 및 실시간 모니터링 (Controller)

<img width="773" height="368" alt="Controller 부하제어" src="https://github.com/user-attachments/assets/77ae9d83-74b3-4b8e-bf65-3e23947e0fe0" />

API별 스크립트를 **Scenario Group**으로 등록하고 그룹마다 Vuser 수를 지정해 부하를 발생시켰습니다.
테스트 중에는 아래 8개 그래프를 한 화면에 띄워 클라이언트 지표와 서버 리소스를 함께 확인했습니다.

| No | 그래프 | 확인 내용 |
|:---:|---|---|
| 1 | Running Vusers | 시간에 따른 가상 사용자 수 (부하 증가 단계 확인) |
| 2 | Trans Response Time | 트랜잭션별 응답 시간 |
| 3 | Trans/Sec (Passed) | 트랜잭션별 초당 처리 건수(TPS) |
| 4 | Total Trans/Sec (Passed) | 전체 TPS |
| 5 | Hits per Second | 초당 HTTP 요청 수 |
| 6 | CPU of SiteScope | 대상 서버 CPU 사용률 |
| 7 | MEM of SiteScope | 대상 서버 메모리 사용률 |
| 8 | Throughput | 초당 응답 데이터 전송량 (Bytes/sec) |

Vuser가 늘어나는데 TPS가 더 이상 오르지 않고 응답 시간만 늘어나는 구간, 또는 CPU / 메모리가 먼저 한계에 도달하는 구간을 보며 병목 지점을 찾았습니다.

### 3. 결과 분석 (Analysis)

<img width="356" height="184" alt="Analysis 결과" src="https://github.com/user-attachments/assets/424d4959-052b-4ce2-84d4-e55c43ff2653" />

테스트가 끝나면 Analysis로 결과 파일을 열어 그래프별로 상세 분석했습니다.

1. **Session Explorer**에서 분석할 그래프(Transactions per Second 등)를 선택
2. **Legend**에서 트랜잭션별 Minimum / Average / Maximum / Median / Std. Deviation 값을 확인

Vuser가 늘어나는 구간(Ramp-up)에서 TPS가 함께 증가하다가, 목표 부하에 도달한 뒤에는 트랜잭션별 TPS가 일정하게 유지되는지 확인했습니다.

### 4. 성능 테스트 결과 Report

<img width="1356" height="792" alt="성능 테스트 Report" src="https://github.com/user-attachments/assets/534a4b2d-ead1-49a4-bb6c-a6010f3503ac" />

테스트 결과를 평가 의견, 검증 도구, 시스템 구성도, API별 결과 상세 내역과 함께 정리해 유관 부서에 공유했습니다.

**요약 (왼쪽)**

- **평가 의견**: 서버 2곳의 회원정보 조회 API를 1건씩 부하 진행해, 목표 TPS **150 TPS / 30 TPS** 대비 평균 응답 속도 **0.3초**로 안정적으로 처리됨을 확인
- **검증 도구**: 부하발생기(LoadRunner), 모니터링(PinPoint / JENNIFER / Grafana)
- **시스템 구성도**: 클라이언트 → VIP / DNS → Web(Apache) → WAS(Tomcat)로 이어지는 요청 흐름과 신규 / 레거시 서버 구성을 함께 정리해,
  부하가 어느 구간을 거치는지와 병목이 생길 수 있는 지점을 리포트에서 바로 확인할 수 있도록 했습니다.

**결과 상세 내역 (오른쪽) - 회원 정보 조회 API, 150 TPS 부하**

- **단계별 부하**: 50 TPS부터 10 TPS씩 올려 150 TPS까지 도달한 시각을 표로 기록해, 그래프에서 어느 부하 단계에서 변화가 생겼는지 바로 대조할 수 있도록 했습니다.
- **LoadRunner 지표**: Running Vusers와 Total TPS가 함께 올라가 목표 150 TPS에 도달한 뒤 유지되고, 평균 응답 시간이 부하 단계와 관계없이 낮게 유지되는 것을 확인했습니다.
- **SiteScope 지표**: 부하 구간 동안 서버 CPU / 메모리 사용률이 급증하지 않고 안정적으로 유지되는 것을 확인했습니다.
- **APM(PinPoint) 지표**: Heap Usage, JVM CPU, System CPU, Response Time을 함께 확인해 GC나 애플리케이션 내부에서 병목이 생기지 않았는지 점검했습니다.

## 서버 접속 스크립트

`scripts/securecrt_login.vbs`는 부하 테스트 중 대상 서버에 접속해 상태를 확인할 때 사용한 SecureCRT 로그인 스크립트입니다.
접속 게이트웨이에서 IP 입력 → 접속 방식(SSH) 선택 → 계정 / 비밀번호 입력 과정을 자동으로 처리합니다.

```vbscript
Sub Main
    crt.Screen.Send "i" & chr(13)
    crt.Screen.WaitForString "Input ipaddress [ip number]: "
    crt.Screen.Send "xxx.xxx.xxx.xxx" & chr(13)
    crt.Screen.WaitForString "Input Service t[telnet]/s[ssh]/f[ftp]/sf[sftp]/rsh/c[cancel]/q[quit]: "
    crt.Screen.Send "s" & chr(13)
    crt.Screen.WaitForString "Login: "
    crt.Screen.Send "xxxxxxx" & chr(13)
    crt.Screen.WaitForString "Password: "
    crt.Screen.Send "xxxxxxxx" & chr(13)
End Sub
```

---

> ※ 본 자료는 포트폴리오용 샘플이며, 민감 정보는 제외 또는 가공되었습니다.
