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


---

## [VITIS-001] HandCipher 앱 빌드 실패: `lmb_bram_0` overflow

**발생 환경:** Vitis 2024.2, MicroBlaze V(RISC-V), standalone bare-metal app

### 증상

Vitis application build 단계에서 플랫폼/BSP 빌드는 성공하지만 앱 링크가 실패했다.

```text
section `.text' will not fit in region `lmb_bram_0'
region `lmb_bram_0' overflowed by 9056 bytes
```

이후 테스트 코드를 줄였을 때도 다음과 같이 남은 초과가 발생했다.

```text
section `.stack' will not fit in region `lmb_bram_0'
region `lmb_bram_0' overflowed by 584 bytes
Memory region lmb_bram_0: 8776 B / 8192 B = 107.13%
```

### 원인 분석

소스 코드 자체는 작았지만, 기본 Vitis bare-metal 앱은 다음 요소를 함께 링크한다.

- startup/runtime 코드 (`crt0`, `_boot`, trap handler)
- standalone BSP 라이브러리
- `print()`/UARTLite 출력 경로
- libc exit/stdio/malloc 관련 일부 코드
- linker script의 기본 heap/stack 예약

기존 local memory가 8KB뿐이었다.

```ld
lmb_bram_0 : ORIGIN = 0x2000, LENGTH = 0x2000
_STACK_SIZE = 0x400;
_HEAP_SIZE  = 0x800;
```

따라서 Hello World 수준 코드도 여유가 거의 없었다.

### 해결

MicroBlaze local memory를 128KB로 확장하고 XSA/platform을 재생성했다.

최종 Vitis linker script:

```ld
lmb_bram_0 : ORIGIN = 0x0, LENGTH = 0x20000
```

`xparameters.h` 확인값:

```c
#define XPAR_LMB_BRAM_0_BASEADDRESS 0x0
#define XPAR_LMB_BRAM_0_HIGHADDRESS 0x1ffff
```

### 검증 방법

Vitis 빌드 후 `lscript.ld`와 `xparameters.h`에서 LMB 크기를 확인한다.

```text
128KB = 0x20000
0x0 ~ 0x1ffff
```

---

## [VIVADO-001] MicroBlaze local memory를 GUI에서 직접 수정할 수 없음

**발생 환경:** Vivado TOP Block Design, `microblaze_riscv_0_local_memory`

### 증상

`lmb_bram` Block Memory Generator를 더블클릭해도 memory size/depth가 수정되지 않았다. MicroBlaze V 설정창의 Cache 탭에서 보이는 8KB도 수정 대상처럼 보였지만 local memory 크기와 무관했다.

### 원인 분석

MicroBlaze V 설정창의 `Instruction Cache`/`Data Cache` 8KB는 캐시 크기이며, LMB local memory 크기가 아니다.

또한 `lmb_bram`의 `Write_Depth_A`는 다음처럼 전파값이었다.

```text
Write_Depth_A = 2048
value_src = propagated
```

즉 BRAM IP에서 직접 바꾸는 값이 아니라 Address Editor의 LMB address segment range가 전파되어 결정되는 구조다.

### 해결

Address Editor 또는 Tcl Console에서 D-LMB/I-LMB address segment range를 바꾼다.

```tcl
set_property range 128K [get_bd_addr_segs microblaze_riscv_0/Data/SEG_dlmb_bram_if_cntlr_Mem]
set_property range 128K [get_bd_addr_segs microblaze_riscv_0/Instruction/SEG_ilmb_bram_if_cntlr_Mem]
validate_bd_design
save_bd_design
```

변경 후 기대값:

```text
dlmb_bram_if_cntlr  Range 128K
ilmb_bram_if_cntlr  Range 128K
```

32-bit BRAM 기준 내부 depth는 대략 다음 값으로 전파된다.

```text
32768 words * 4 bytes = 131072 bytes = 128KB
```

---

## [VITIS-002] UART 메뉴 입력 후 `-35`, `-38`이 출력됨

**발생 환경:** Vitis UARTLite terminal, `inbyte() - '0'` 메뉴 입력

### 증상

메뉴에서 `1`, `2`, `3`을 입력한 뒤 다음 루프에서 아래 값이 추가로 출력됐다.

```text
(1~4): -35
(1~4): -38
```

### 원인 분석

터미널에서 숫자 입력 후 Enter를 누르면 `\r`와 `\n`도 UART RX에 남는다.

```text
'\r' = 13, 13 - '0'(48) = -35
'\n' = 10, 10 - '0'(48) = -38
```

### 해결

연결성 확인 단계에서는 메뉴 입력을 없애고 자동 테스트 앱으로 변경했다. 메뉴형 앱을 다시 쓸 경우 `inbyte()` 결과에서 `\r`/`\n`을 무시해야 한다.

```c
char c;
do {
    c = inbyte();
} while (c == '\r' || c == '\n');
choice = c - '0';
```

---

## [AXI-001] VGA/TFT 0번 레지스터에 임의값 write/readback 테스트 실패

**발생 환경:** Vitis AXI 연결성 테스트

### 증상

NPU는 다음 테스트가 통과했다.

```text
NPU write 0xAAAABBBB -> read 0xAAAABBBB
```

하지만 TFT/VGA는 임의값 write/readback이 실패처럼 보였다.

```text
TFT write 0x55556666 -> read 0x00000002
VGA write 0x12345678 -> read 0x00000000
```

### 원인 분석

NPU `0x00`은 CTRL readback 레지스터라 임의값 readback이 가능하다.

반면 TFT/VGA의 `0x00`은 단순 저장 레지스터가 아니라 제어/상태 레지스터다.

TFT/VGA CTRL read 구조:

```verilog
axi_rdata <= {30'd0, clear_busy, reg_enable};
```

따라서 bit0 enable, bit1 clear_busy만 읽히며, 쓴 32-bit 값 전체가 되돌아오지 않는다. 특히 `0x12345678`은 bit0이 0이라 VGA enable을 꺼버린다.

### 해결

각 IP의 레지스터 맵에 맞춘 연결성 테스트로 변경했다.

- NPU: CTRL readback 확인
- TFT: CTRL enable bit와 STATUS read 확인
- VGA: CTRL enable bit, CANVAS_MODE readback, 문자/캔버스 write smoke test 확인

최종 UART 검증 결과:

```text
HandCipher connectivity test
NPU base=0x00020000
VGA base=0x00021000
TFT base=0x00030000
NPU CTRL      read=0xAAAABBBB expected=0xAAAABBBB
TFT CTRL      read=0x00000001 enable=1
TFT STATUS    read=0x00000002
VGA CTRL      read=0x00000001 enable=1
VGA TEXTMODE  read=0x00000000
VGA CANVAS    read=0x00000001 mode=1

RESULT NPU=OK TFT=OK VGA=OK
```

판정: AXI 주소 매핑과 MicroBlaze -> NPU/TFT/VGA slave 접근은 정상.

---

## [NPU-001] 보드/RTL NPU 결과가 Python 정수 모델과 다름

**발생 환경:** IP_TEST RTL simulation 및 TOP 통합 전 NPU 검증

### 증상

보드에서 어떤 글자를 그려도 `T` 등 일부 결과로 치우치는 현상이 있었다. RTL 시뮬레이션에서도 synthetic pattern 입력 결과가 Python 정수 모델과 맞지 않았다.

예시 RTL simulation 결과:

```text
A -> A
M -> T
N -> L
V -> C
T -> D
```

### 원인 분석

학습/export 데이터 자체는 Python에서 정상으로 확인됐다.

- float test accuracy: 약 87.90%
- integer export accuracy: 약 87.74%
- M/N/V/T 등 주요 글자 class accuracy도 정상 범위
- `.mem` 파일 누락 문제 해결 후 synth log에서 weight/bias readmem 성공 확인

따라서 모델 데이터보다는 RTL NPU 내부의 ROM/BRAM read latency 또는 MAC accumulation 타이밍 불일치 가능성이 높다.

### 현재 상태

- 최종 연결성 검증에서는 NPU AXI slave read/write 접근만 확인 완료
- NPU 추론 정확도 문제는 별도 보류
- 데모 신뢰성이 우선이면 Vitis software inference로 우회하거나, RTL NPU 타이밍을 별도 수정/검증해야 한다.

---

## [NPU-002] NPU weight/bias `.mem` 파일을 Vivado가 못 읽음

**발생 환경:** Vivado synthesis, NPU ROM `$readmemh`

### 증상

synthesis log에 다음 유형의 critical warning이 발생했다.

```text
could not open weights_l1.mem
could not open biases_l1.mem
could not open weights_l2.mem
could not open biases_l2.mem
```

NPU 결과가 `A` 등 고정된 값처럼 보였다.

### 원인 분석

`training/exported/*.mem` 파일은 존재했지만 Vivado project source/import 경로에 등록되지 않아 synthesis working directory에서 `$readmemh`가 파일을 찾지 못했다.

### 해결

`IP_TEST.xpr`에 NPU memory files를 source로 등록했다.

- `weights_l1.mem`
- `biases_l1.mem`
- `weights_l2.mem`
- `biases_l2.mem`
- `font_rom.mem`

이후 synthesis log에서 `$readmem` 성공 메시지를 확인했다.

---

## [VGA-001] VGA UI가 사라지고 캔버스/그림만 보임

**발생 환경:** IP_TEST demo top / VGA demo integration

### 증상

VGA에서 그린 캔버스는 보이지만, 결과 문구/UI 텍스트가 보이지 않는 상태가 있었다.

### 원인 분석

데모 top의 VGA text initialization FSM이 clear busy 상태와 맞물려 텍스트 쓰기 타이밍이 꼬일 가능성이 있었다.

### 해결

데모 top의 VGA text init FSM에 timeout/대기 처리를 추가해 clear 완료 후 텍스트 쓰기 흐름이 진행되도록 보강했다.

현재 TOP/Vitis 연결성 테스트에서는 VGA AXI 문자 버퍼 write 경로를 별도로 확인했다.

---

## [DRAW-001] 3x3 brush / interpolation 실험 후 원복

**발생 환경:** `draw_canvas.v` 실험 수정

### 증상

손글씨 인식률 개선을 위해 3x3 brush 및 Bresenham interpolation을 실험했지만, 보드 기준 충분한 검증 전이라 결과 판단이 어려웠다.

### 조치

`draw_canvas.v`를 원래 방식으로 되돌렸다.

- 터치 샘플 1개 -> 28x28 canvas pixel 1개 write
- CLEAR/OK pulse 동작 유지
- 굵기 보정은 추후 별도 검증 후 재도입 예정
