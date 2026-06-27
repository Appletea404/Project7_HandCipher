# HandCipher — FPGA Handwritten Letter Recognition & Caesar Cipher System (v6)

## Context

**HandCipher** — SoC-Based handwritten letter recognition and Caesar cipher system using a custom EMNIST NPU, touchscreen input and VGA output on Basys3.

EMNIST NPU, VGA, TFT-LCD를 각각 AXI Custom IP로 패키징해 Vivado Block Design에 연결하고, MicroBlaze에서 Vitis C 코드로 암호화 로직과 UI를 제어하는 시스템.

**역할 분리:**

- **RTL (Custom IP)**: NPU 추론, VGA 신호 생성, ILI9341/XPT2046 SPI 제어
- **C 소프트웨어 (Vitis)**: 카이사르 암호화/복호화, 화면 구성, 버튼/스위치 처리, 모드 제어

**시스템 흐름:**

```
[암호화] 글자 그리기(TFT IP) → btnC → NPU IP 추론 → C코드 Caesar 암호화 → VGA IP 출력
[복호화] SW[14]=1 → 버퍼 내 암호문 C코드 역변환 → VGA IP 출력
```

---

## 하드웨어 구성

| 하드웨어                 | 역할                               |
| ------------------------ | ---------------------------------- |
| ILI9341 (240×320, PMOD) | 글자 그리기 캔버스                 |
| XPT2046 (PMOD 공유)      | 터치 좌표 입력                     |
| VGA 모니터 (640×480)    | 텍스트/결과 출력                   |
| btnC/U/D/L/R             | OK / 모드전환 / CLEAR / 버퍼초기화 |
| SW[4:0]                  | 카이사르 시프트 값 (0~25)          |
| SW[14]                   | 0=암호화, 1=복호화                 |
| SW[15]                   | 전체 리셋                          |

---

## Block Design 구성 (Vivado)

```
┌─────────────────────────────────────────────────────┐
│                  AXI Interconnect                    │
│                                                     │
│  MicroBlaze ──┬──► NPU IP      (0x43C0_0000)       │
│  (32KB BRAM)  ├──► VGA IP      (0x43C1_0000)       │
│               ├──► TFT-LCD IP  (0x43C2_0000)       │
│               └──► AXI GPIO    (0x40000000)         │
│                    (buttons + switches)              │
└─────────────────────────────────────────────────────┘

캔버스 BRAM: TFT-LCD IP(Port A 쓰기) ↔ NPU IP(Port B 읽기) 공유
→ CPU가 784바이트 전송 불필요, "추론 시작" 명령만 전송
```

---

## BRAM 리소스 (Artix-7 35T: BRAM18 100개)

| 내용                          | BRAM18             |
| ----------------------------- | ------------------ |
| MicroBlaze 로컬 메모리 (32KB) | 16                 |
| NPU L1 weight ROM (784×64)   | 25                 |
| NPU L2 weight ROM (64×26)    | 1                  |
| 캔버스 BRAM (28×28, 공유)    | 1                  |
| VGA 문자 버퍼 (80×60)        | 3                  |
| VGA 폰트 ROM (8×8 × 128)    | 1                  |
| **합계**                | **47 / 100** |

---

## 전체 파일 구조

3개 IP의 RTL 검증을 IP_TEST 하나의 Vivado 프로젝트에서 모두 진행한 뒤, 각각 Custom IP로 패키징해 TOP에서 통합한다.

```
Project_7_HandCipher/
├── Vivado/
│   ├── IP_TEST/                           ← Vivado 프로젝트 #1 (3개 IP RTL 검증)
│   │   ├── IP_TEST.xpr
│   │   ├── IP_TEST.srcs/sources_1/
│   │   │   ├── imports/
│   │   │   │   └── tft_lcd_sv.sv          (spi, xpt2046 재사용)
│   │   │   └── new/
│   │   │       ├── mem/                   (quantize_export.py 생성)
│   │   │       │   ├── weights_l1.mem
│   │   │       │   ├── weights_l2.mem
│   │   │       │   ├── biases_l1.mem
│   │   │       │   └── biases_l2.mem
│   │   │       ├── npu_params.vh
│   │   │       ├── npu_ctrl.v             (EMNIST 추론 FSM)
│   │   │       ├── image_buffer.v         (캔버스 BRAM, 듀얼포트)
│   │   │       ├── weight_rom_l1.v
│   │   │       ├── weight_rom_l2.v
│   │   │       ├── bias_rom.v
│   │   │       ├── npu_axi.v              (NPU AXI4-Lite 래퍼)
│   │   │       ├── tb_npu.v
│   │   │       ├── canvas_display.v       (ILI9341 SPI 스트리밍)
│   │   │       ├── draw_canvas.v          (터치 좌표 → BRAM Port A)
│   │   │       ├── tft_axi.v              (TFT AXI4-Lite 래퍼)
│   │   │       ├── tb_tft.v
│   │   │       ├── font_rom.v
│   │   │       ├── vga_ctrl.v             (640×480 타이밍 + 문자 렌더러)
│   │   │       ├── vga_axi.v              (VGA AXI4-Lite 래퍼)
│   │   │       └── tb_vga.v
│   │   └── IP_TEST.srcs/constrs_1/
│   │       └── imports/basys3.xdc
│   │
│   └── TOP/                               ← Vivado 프로젝트 #2 (통합 + .xsa 생성)
│       ├── TOP.xpr
│       ├── TOP.srcs/sources_1/new/bd/     (Block Design)
│       │   MicroBlaze + AXI Interconnect
│       │   + npu_ip / tft_ip / vga_ip (Custom IP)
│       │   + AXI GPIO (버튼 + 스위치)
│       ├── TOP.srcs/constrs_1/new/
│       │   └── basys3.xdc
│       └── handcipher.xsa                 (Vitis로 내보내기)
│
├── Vitis/
│   └── src/
│       ├── main.c
│       ├── caesar.c
│       ├── caesar.h
│       ├── display.c
│       └── display.h
└── training/
    ├── training_emnist.py                 (✅ 완료 → model.pth 생성됨)
    ├── quantize_export.py
    └── test_inference.py
```

---

## Part 1: 학습 파이프라인 (변경 없음)

### 데이터셋: EMNIST Letters (A~Z, 26클래스)

```python
from torchvision.datasets import EMNIST
# split='letters', 레이블 1~26 → 0~25 재매핑
# 이미지 전치 처리 필수 (.T)
transform = transforms.Compose([
    transforms.ToTensor(),
    transforms.Lambda(lambda x: x.squeeze().T.reshape(1, 28, 28))
])
```

### 신경망: MLP 784 → 64 → 26

```python
class MLP(nn.Module):
    def __init__(self):
        self.fc1 = nn.Linear(784, 64)
        self.fc2 = nn.Linear(64, 26)
    def forward(self, x):
        return self.fc2(F.relu(self.fc1(x.view(-1, 784))))
# Adam(lr=1e-3), 20 epochs, 목표 ≥85%
```

### 양자화 계약

```
L1: hidden[n] = clamp(relu(Σ(uint8(px)×int8(w1)) + bias_l1) >> SHIFT_L1, 0, 255)
L2: score[o]  = Σ(uint8(hidden)×int8(w2)) + bias_l2   (o: 0~25)
letter = argmax(score)  → 0=A, 25=Z
```

---

## Part 2: Custom IP 설계

### IP #1: `npu_ip` — NPU 추론 엔진

**AXI 레지스터 맵:**

```
0x00: CTRL    [0]=start (1 쓰면 추론 시작)
0x04: STATUS  [0]=done, [1]=busy
0x08: RESULT  [4:0]=letter (0~25, done=1일 때 유효)
```

**`npu_axi.v` 동작:**

- AXI write CTRL[0]=1 → npu_ctrl에 start 펄스 발생
- npu_ctrl DONE 신호 → STATUS[0]=1, RESULT 레지스터 업데이트
- AXI read → STATUS, RESULT 값 반환

**`npu_ctrl.v` FSM (변경 없음):**

```
IDLE → LOAD_CANVAS → L1×64 → L2×26 → ARGMAX → DONE → IDLE
```

**캔버스 BRAM 공유:**

- `image_buffer.v`: 듀얼포트 BRAM (784-bit, 1-bit wide)
- Port A: `tft_ip`의 `draw_canvas`가 터치 픽셀 1-bit 쓰기
- Port B: `npu_ctrl`이 읽기 (1→0xFF, 0→0x00 변환 후 uint8 사용)

**`npu_axi.v` 추가 포트 (AXI4-Lite 슬레이브 외):**

```verilog
// 캔버스 BRAM Port B 연결
output [9:0]  canvas_rd_addr,
input         canvas_rd_data,    // 1-bit

// NPU 결과
output [4:0]  letter,
output        done
```

---

### IP #2: `vga_ip` — VGA 문자 모드 디스플레이

**AXI 레지스터 맵:**

```
0x00: CTRL      [0]=enable, [1]=clear (전체 스페이스로 채움)
0x04: CHAR_ADDR [12:0] 문자 버퍼 주소 (0~4799, 80×60)
0x08: CHAR_DATA [7:0]  쓸 문자 ASCII
0x0C: WR_STRB   [0]=1 쓰기 실행 (자동 클리어)
0x10: FG_COLOR  [11:0] 전경색 RGB444
0x14: BG_COLOR  [11:0] 배경색 RGB444
```

**`vga_axi.v` 동작:**

- CPU가 CHAR_ADDR, CHAR_DATA 레지스터 설정 후 WR_STRB=1 → 문자 버퍼(BRAM)에 기록
- `vga_ctrl`이 문자 버퍼 + 폰트 ROM 참조해 픽셀 생성 → VGA 출력

**`vga_ctrl.v` (640×480 @ 60Hz, 8×8 폰트, 80×60 문자):**

- 픽셀 클록: 100MHz ÷ 4 = 25MHz (클록 분주기 내장)
- `H_TOTAL=800, V_TOTAL=525` (표준 640×480 @ 60Hz 타이밍)
- 렌더링: `char_buf[row*80+col]` → `font_rom[(char-32)*8+row_in]` → `pixel_on`

---

### IP #3: `tft_ip` — ILI9341 캔버스 + XPT2046 터치

**AXI 레지스터 맵:**

```
0x00: CTRL      [0]=enable, [1]=clear_canvas
0x04: TOUCH_X   [11:0] raw ADC X (읽기 전용)
0x08: TOUCH_Y   [11:0] raw ADC Y (읽기 전용)
0x0C: STATUS    [0]=touch_valid, [1]=lcd_ready
```

**`tft_axi.v` 동작:**

- `xpt2046`가 터치 감지 → TOUCH_X/Y 레지스터 업데이트, STATUS[0]=1
- `draw_canvas`가 터치 좌표 → 캔버스 BRAM Port A 1-bit 쓰기
- `canvas_display`가 캔버스 BRAM 읽어 ILI9341로 SPI 스트리밍
- CTRL[1]=1 → `draw_canvas`가 캔버스 BRAM 전체 0으로 초기화

**캔버스 BRAM Port A (tft_ip 내부):**

- `draw_canvas` → 캔버스 BRAM Port A (1-bit write, addr = row×28+col)
- `xpt2046` 모듈: `tft_lcd_sv.sv`에서 그대로 재사용, 50MHz 공급 (100MHz ÷ 2)

---

## Part 3: Vitis C 소프트웨어

### `main.c`

```c
#include "xparameters.h"
#include "xgpio.h"
#include "caesar.h"
#include "display.h"

// IP 베이스 주소 (xparameters.h에서 자동 생성)
#define NPU_BASE   XPAR_NPU_IP_0_BASEADDR
#define VGA_BASE   XPAR_VGA_IP_0_BASEADDR
#define TFT_BASE   XPAR_TFT_IP_0_BASEADDR

// 레지스터 오프셋
#define NPU_CTRL   (NPU_BASE + 0x00)
#define NPU_STATUS (NPU_BASE + 0x04)
#define NPU_RESULT (NPU_BASE + 0x08)
#define TFT_STATUS (TFT_BASE + 0x0C)

char plain_buf[64]  = {0};
char cipher_buf[64] = {0};
int  buf_len = 0;

int main() {
    XGpio gpio;
    XGpio_Initialize(&gpio, XPAR_AXI_GPIO_0_DEVICE_ID);

    display_init(VGA_BASE);  // VGA 초기화, 초기 화면 출력

    while (1) {
        u32 sw  = XGpio_DiscreteRead(&gpio, 2);  // 스위치
        u32 btn = XGpio_DiscreteRead(&gpio, 1);  // 버튼 (디바운스)

        int shift = sw & 0x1F;          // SW[4:0]
        int mode  = (sw >> 14) & 0x1;  // SW[14]: 0=암호화, 1=복호화

        // OK 버튼: NPU 추론 → 암호화/복호화
        if (btn & BTN_C) {
            Xil_Out32(NPU_CTRL, 1);          // 추론 시작
            while (!(Xil_In32(NPU_STATUS) & 0x1)); // done 대기
            int letter = Xil_In32(NPU_RESULT) & 0x1F; // 0~25

            char plain_c  = 'A' + letter;
            char cipher_c = mode ? caesar_decode(plain_c, shift)
                                 : caesar_encode(plain_c, shift);

            if (buf_len < 64) {
                plain_buf[buf_len]  = plain_c;
                cipher_buf[buf_len] = cipher_c;
                buf_len++;
            }
            display_update(VGA_BASE, plain_buf, cipher_buf,
                           buf_len, shift, mode, plain_c, cipher_c);
            Xil_Out32(TFT_BASE + 0x00, 0x2); // 캔버스 CLEAR
        }

        // CLEAR 버튼: 캔버스만 초기화
        if (btn & BTN_L)
            Xil_Out32(TFT_BASE + 0x00, 0x2);

        // 버퍼 초기화 버튼
        if (btn & BTN_R) {
            buf_len = 0;
            display_update(VGA_BASE, plain_buf, cipher_buf,
                           0, shift, mode, '-', '-');
        }
    }
}
```

---

### `caesar.c` / `caesar.h`

```c
char caesar_encode(char c, int shift) {
    return 'A' + (c - 'A' + shift) % 26;
}

char caesar_decode(char c, int shift) {
    return 'A' + (c - 'A' + 26 - shift) % 26;
}
```

---

### `display.c` / `display.h`

VGA IP에 문자 기록하는 헬퍼 함수

```c
void vga_putchar(u32 base, int row, int col, char c, u32 fg, u32 bg);
void vga_puts(u32 base, int row, int col, const char *str, u32 fg, u32 bg);
void vga_clear(u32 base);

void display_init(u32 vga_base) {
    vga_clear(vga_base);
    vga_puts(vga_base, 0, 20, "=== CAESAR CIPHER SYSTEM ===", WHITE, DARK_BLUE);
    vga_puts(vga_base, 58, 0,
             "btnC=OK  btnL=CLR  btnR=BUF_CLR  SW[4:0]=SHIFT  SW[14]=MODE",
             GRAY, BLACK);
}

void display_update(u32 base, char *plain, char *cipher, int len,
                    int shift, int mode, char last_in, char last_out) {
    char line[82];

    // 모드 + 시프트
    sprintf(line, "MODE: %-9s  SHIFT: +%d  ",
            mode ? "DECRYPT" : "ENCRYPT", shift);
    vga_puts(base, 2, 0, line, CYAN, BLACK);

    // 마지막 입출력
    sprintf(line, "Last Input  : %c", last_in);
    vga_puts(base, 4, 0, line, WHITE, BLACK);
    sprintf(line, mode ? "Decrypted   : %c" : "Encrypted   : %c", last_out);
    vga_puts(base, 5, 0, line, YELLOW, BLACK);

    // 누적 버퍼
    plain[len]  = '\0';
    cipher[len] = '\0';
    sprintf(line, "Plaintext   : %-64s", plain);
    vga_puts(base, 7, 0, line, GREEN, BLACK);
    sprintf(line, "Ciphertext  : %-64s", cipher);
    vga_puts(base, 8, 0, line, CYAN, BLACK);
}
```

---

## Part 4: 테스트벤치

### `tb_npu_ip.v`

- AXI write CTRL=1 → 추론 시작
- STATUS done 확인, RESULT 0~25 범위 검증

### `tb_vga_ip.v`

- AXI로 문자 기록 후 VGA 픽셀 스트림 검증
- hsync/vsync 주기 확인 (640×480 @ 60Hz)

### `tb_tft_ip.v`

- XPT2046 터치 시뮬레이션 → TOUCH_X/Y 레지스터 업데이트 확인
- 캔버스 BRAM Port A 쓰기 확인

---

## 구현 순서

### Phase 1 — 학습 (PC) ✅ model.pth 완료

1. ~~`training_emnist.py` → model.pth~~ ✅ 완료
2. `quantize_export.py` → .mem 4개 + npu_params.vh 생성
3. `test_inference.py` → ≥80% 정수 시뮬레이션 확인

### Phase 2 — IP RTL 구현 및 검증 (Vivado/IP_TEST/)

**NPU IP:**

4. `npu_ctrl.v`, `weight_rom_l1.v`, `weight_rom_l2.v`, `bias_rom.v`, `image_buffer.v`
5. `npu_axi.v` (AXI4-Lite 래퍼)
6. `tb_npu.v` → XSim: AXI start → done, RESULT 0~25 확인
7. **Create and Package New IP** → `npu_ip_v1_0`

**TFT-LCD IP:**

8. `canvas_display.v`, `draw_canvas.v` (tft_lcd_sv.sv의 spi/xpt2046 재사용)
9. `tft_axi.v` (AXI4-Lite 래퍼)
10. `tb_tft.v` → XSim: 터치 시뮬레이션 → BRAM Port A 쓰기 확인
11. **Create and Package New IP** → `tft_ip_v1_0`

**VGA IP:**

12. `font_rom.v`, `vga_ctrl.v` (640×480 @ 60Hz, 문자 렌더러)
13. `vga_axi.v` (AXI4-Lite 래퍼)
14. `tb_vga.v` → XSim: AXI 문자 기록 → VGA 픽셀 스트림 확인
15. **Create and Package New IP** → `vga_ip_v1_0`

### Phase 3 — TOP 통합 (Vivado/TOP/)

16. TOP 프로젝트 생성, IP Repository에 npu_ip / tft_ip / vga_ip 추가
17. Block Design 생성:
    - MicroBlaze (32KB BRAM)
    - AXI Interconnect
    - npu_ip, tft_ip, vga_ip 각각 Add IP
    - AXI GPIO (버튼 + 스위치)
    - 캔버스 BRAM: tft_ip Port A ↔ npu_ip Port B 외부 연결
18. `basys3.xdc` 핀 제약 추가
19. 합성 + 구현 → BRAM18 ≤50, WNS ≥ 0 확인
20. **File → Export → Export Hardware** → `handcipher.xsa` 생성

### Phase 4 — Vitis C 코드 (Vitis/)

21. Vitis에서 handcipher.xsa로 Platform 프로젝트 생성
22. Application 프로젝트 생성 → `caesar.c` / `caesar.h`
23. `display.c` / `display.h`
24. `main.c`
25. 빌드 + Basys3에 Program Device

### Phase 5 — 하드웨어 검증

26. 글자 그리기 → btnC → VGA 암호화 결과 확인
27. SW[14]=1 복호화 모드 전환 확인
28. SW[4:0] 시프트 값 변경 실시간 반영 확인

---

## 검증 기준

| 단계         | 기준                                     |
| ------------ | ---------------------------------------- |
| 학습         | float ≥85%, 정수 시뮬레이션 ≥80%       |
| NPU IP       | AXI start → done, RESULT 0~25           |
| VGA IP       | 640×480 @ 60Hz, 문자 정상 출력          |
| TFT IP       | 터치 → 캔버스 BRAM 정상 기록            |
| Block Design | 합성 BRAM18 ≤50, WNS ≥ 0               |
| C 코드       | H→K(shift=3), K→H(decrypt) 정상        |
| 하드웨어     | 글자 그리기 → OK → VGA 결과 (3초 이내) |

---

## 버전별 변경 요약

| 항목        | v5 (순수 RTL)    | v6 (Custom IP + Vitis)  |
| ----------- | ---------------- | ----------------------- |
| 제어 로직   | Verilog FSM      | MicroBlaze C 코드       |
| 암호화 로직 | cipher_encoder.v | caesar.c (수정 용이)    |
| 화면 구성   | text_buffer.v    | display.c (printf 수준) |
| 디버깅      | XSim 시뮬레이션  | UART printf 가능        |
| IP 구조     | 단일 top.v       | 3× Custom IP + BD      |
| BRAM        | 31 / 100         | 47 / 100                |
| Vivado 작업 | RTL only         | RTL + Block Design      |
| Vitis 작업  | 없음             | C 코드 작성             |

---

## basys3.xdc (주요 핀)

```tcl
# Clock
set_property PACKAGE_PIN W5   [get_ports clk]
create_clock -period 10.000   [get_ports clk]

# Buttons
set_property PACKAGE_PIN U18  [get_ports btnC]
set_property PACKAGE_PIN T18  [get_ports btnU]
set_property PACKAGE_PIN U17  [get_ports btnD]
set_property PACKAGE_PIN W19  [get_ports btnL]
set_property PACKAGE_PIN T17  [get_ports btnR]

# Switches SW[0..4] = shift, SW[14]=mode, SW[15]=reset
set_property PACKAGE_PIN V17  [get_ports {sw[0]}]
set_property PACKAGE_PIN V16  [get_ports {sw[1]}]
set_property PACKAGE_PIN W16  [get_ports {sw[2]}]
set_property PACKAGE_PIN W17  [get_ports {sw[3]}]
set_property PACKAGE_PIN W15  [get_ports {sw[4]}]
set_property PACKAGE_PIN V15  [get_ports {sw[14]}]
set_property PACKAGE_PIN R2   [get_ports {sw[15]}]

# VGA
set_property PACKAGE_PIN G19  [get_ports {vga_r[0]}]
set_property PACKAGE_PIN H19  [get_ports {vga_r[1]}]
set_property PACKAGE_PIN J19  [get_ports {vga_r[2]}]
set_property PACKAGE_PIN N19  [get_ports {vga_r[3]}]
set_property PACKAGE_PIN J17  [get_ports {vga_g[0]}]
set_property PACKAGE_PIN H17  [get_ports {vga_g[1]}]
set_property PACKAGE_PIN G17  [get_ports {vga_g[2]}]
set_property PACKAGE_PIN D17  [get_ports {vga_g[3]}]
set_property PACKAGE_PIN N18  [get_ports {vga_b[0]}]
set_property PACKAGE_PIN L18  [get_ports {vga_b[1]}]
set_property PACKAGE_PIN K18  [get_ports {vga_b[2]}]
set_property PACKAGE_PIN J18  [get_ports {vga_b[3]}]
set_property PACKAGE_PIN P19  [get_ports vga_hs]
set_property PACKAGE_PIN R19  [get_ports vga_vs]

# SPI LCD/Touch (PMOD JA)
set_property PACKAGE_PIN J1   [get_ports tft_sdi]
set_property PACKAGE_PIN L2   [get_ports tft_sdo]
set_property PACKAGE_PIN J2   [get_ports tft_sck]
set_property PACKAGE_PIN G2   [get_ports tft_cs]
set_property PACKAGE_PIN H1   [get_ports touch_cs_n]
set_property PACKAGE_PIN K2   [get_ports tft_dc]
set_property PACKAGE_PIN H2   [get_ports tft_reset]
set_property PACKAGE_PIN G3   [get_ports touch_pen_irq_n]

set_property IOSTANDARD LVCMOS33 [get_ports {clk sw[*] btn* vga_* tft_* touch_*}]
```

---

## tft_lcd_sv.sv 재사용 범위

| 모듈         | 사용 여부                          |
| ------------ | ---------------------------------- |
| `spi`      | ✅ canvas_display.v에서 재사용     |
| `tft_sv`   | ❌ (캔버스 전용 스트리밍으로 대체) |
| `lcd_bram` | ❌ (듀얼포트 image_buffer로 대체)  |
| `xpt2046`  | ✅ 그대로 재사용 (50MHz 분주 공급) |

---

## IP_TEST TFT/Touch 검증 메모

`Vivado/IP_TEST`에서 `tft_lcd_top_HY` 기반으로 TFT 터치 캔버스를 먼저 검증했다.

### 제거한 디버그 기능

- FND 좌표 표시 제거
  - `tft_lcd_top_HY` 포트에서 `com`, `seg` 제거
  - `bin_to_dec`, `FND_cntr` 인스턴스 제거
  - XDC의 `seg[0..7]`, `com[0..3]` 제약 주석 처리

### 터치 노이즈 관련 확인

- 터치 핀을 물리적으로 분리하면 화면 지지직 노이즈가 사라짐
- BRAM write를 꺼도 터치 시 노이즈가 남았으므로, 28x28 캔버스 write 문제가 아니라 터치 SPI 동작 자체가 LCD 표시 쪽에 간섭하는 것으로 판단
- `PenIrq_n`에는 `PULLUP true` 적용
- 터치 샘플링 주기를 기본 약 10ms에서 약 15ms로 완화

```verilog
xpt2046 #(
    .CONV_TIMES(20),
    .FILTER_PARAM(3),
    .CNT_TOP(20'd749999)
) touch_pad(...);
```

### 현재 가장 나은 설정

- `CNT_TOP = 20'd749999`  
  50MHz 기준 약 15ms 샘플링 간격
- `CONV_TIMES = 20`  
  기존 36회 평균보다 터치 SPI burst 시간을 줄임
- `FILTER_PARAM = 3`  
  20회 샘플에서 최대/최소 제거 후 8로 나누는 근사 평균
- XPT2046 DCLK 분주값은 원래 값 유지
  - `DIV_CNT == 5'd24`
  - `5'd31`로 늦추면 오히려 노이즈가 심해졌음

### BRAM write 정책

- `PenIrq_n`이 눌린 동안 계속 쓰지 않음
- `Get_Flag`가 발생한 시점의 좌표를 latch
- 50MHz 터치 도메인에서 toggle 생성 후 100MHz `clk` 도메인으로 동기화
- 새 샘플당 1클럭만 28x28 BRAM에 write
- 3x3 브러시는 획이 너무 두꺼워져 EMNIST 인식에 불리할 수 있어 사용하지 않음

### IP 제작 시 반영할 사항

- TFT IP의 캔버스 write는 `Get_Flag` 기반 1회 write 구조 유지
- `xpt2046`는 위 parameter 설정을 기본값으로 사용
- FND/debug 출력은 IP에 포함하지 않음
- 터치 노이즈가 다시 커지면 `CNT_TOP`을 12~20ms 범위에서 조정하며 보드 기준으로 재검증
