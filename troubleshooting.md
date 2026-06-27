# HandCipher Troubleshooting

---

## [TFT-001] 터치 동작 시 LCD 화면 지지직 노이즈

**발생 환경:** IP_TEST (ILI9341 + XPT2046, PMOD JB/JC)

### 증상

터치스크린을 손가락으로 누르는 동안 LCD 화면에 지지직 노이즈(글리치)가 발생함.

### 원인 분석

1. 터치 핀(PMOD JC)을 보드에서 물리적으로 분리하면 노이즈가 완전히 사라짐
2. BRAM write를 비활성화해도 터치 시 노이즈가 그대로 남았음
3. → 28×28 캔버스 write 로직의 문제가 아니라, **XPT2046 SPI 동작 자체가 LCD SPI 쪽에 전기적으로 간섭**하는 것으로 판단

---

### 해결 1 — LCD SPI 클럭을 50MHz → 25MHz로 감속

**파일:** `tft_lcd_sv.sv` → `spi` 모듈

**방법:** SPI FSM에 1비트 분주 enable(`spi_clk_en`)을 추가해 2클럭에 한 번만 FSM을 진행시킴.

```verilog
reg spi_clk_en;

always @(posedge clk, posedge reset_p) begin
    if (reset_p) begin
        spi_clk_en <= 1'b0;
        // ... 기타 초기화
    end else begin
        spi_clk_en <= ~spi_clk_en;   // 매 클럭 토글

        if (spi_clk_en) begin
            // 기존 SPI 전송 FSM 진행 (2클럭에 1번)
        end
    end
end
```

- 100MHz 시스템 클럭 기준 `tft_sck` ≈ **25MHz**
- 적용 후 노이즈 현저히 감소

**IP화 시 반영:** `canvas_display.v`의 SPI 모듈에 동일 구조 적용. LCD SPI는 25MHz로 고정.

---

### 해결 2 — XPT2046 샘플링 주기 완화

터치 SPI burst 빈도를 줄여 간섭 횟수를 줄임.

**기존:** 기본 설정(약 10ms 주기, CONV_TIMES=36)

**변경 후:**

```verilog
xpt2046 #(
    .CONV_TIMES(20),       // 36 → 20: burst 시간 단축
    .FILTER_PARAM(3),      // 20회 중 최대/최소 제거 후 8로 나누는 근사 평균
    .CNT_TOP(20'd749999)   // 50MHz 기준 약 15ms 샘플링 간격 (기존 10ms → 완화)
) touch_pad(...);
```

| 파라미터 | 변경 전 | 변경 후 | 이유 |
|---|---|---|---|
| `CONV_TIMES` | 36 | 20 | burst 시간 단축, 간섭 횟수 감소 |
| `CNT_TOP` | 기본값(~10ms) | `749999`(~15ms) | 샘플링 간격 완화 |
| `FILTER_PARAM` | — | 3 | 노이즈 필터링 유지 |

**주의:** XPT2046 DCLK 분주값(`DIV_CNT == 5'd24`)은 그대로 유지.
`5'd31`로 늦췄더니 오히려 노이즈가 심해졌음.

---

### 해결 3 — PenIrq_n 풀업 적용

```xdc
set_property -dict { PACKAGE_PIN M19 IOSTANDARD LVCMOS33 PULLUP true } [get_ports PenIrq_n]
```

터치하지 않을 때 PenIrq_n이 플로팅되지 않도록 풀업을 걸어 안정화.

---

### 해결 4 — BRAM write 정책 (오발화 방지)

터치 좌표가 흔들릴 때 불필요한 BRAM write가 반복되지 않도록 구조를 제한함.

- `PenIrq_n` HIGH → write 안 함
- `Get_Flag` 발생 시점의 좌표만 latch해서 1클럭만 write
- 50MHz 터치 도메인에서 toggle 생성 → 100MHz `clk` 도메인으로 동기화
- 3×3 브러시 미사용 (획이 두꺼워 EMNIST 인식 불리)

---

### 현재 확정 설정 (IP_TEST 기준)

| 항목 | 설정값 |
|---|---|
| LCD SPI 클럭 | ≈ 25MHz (`spi_clk_en` 분주) |
| XPT2046 DCLK 분주 | `DIV_CNT == 5'd24` |
| `CONV_TIMES` | 20 |
| `FILTER_PARAM` | 3 |
| `CNT_TOP` | `20'd749999` (~15ms) |
| `PenIrq_n` | `PULLUP true` |
| BRAM write 방식 | `Get_Flag` 기반 1클럭 write |

---

### 노이즈가 다시 발생할 경우

`CNT_TOP`을 12~20ms 범위(`600000`~`1000000`)에서 조정하며 보드 기준으로 재검증.
LCD SPI 분주비를 더 낮추려면 `spi_clk_en` 대신 카운터 기반 분주(÷4, ≈12.5MHz)를 고려.
