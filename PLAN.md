# HandCipher — FPGA Handwritten Letter Recognition & Caesar Cipher System (v6)

## Context

**HandCipher** — SoC-Based handwritten letter recognition and Caesar cipher system using a custom EMNIST NPU, touchscreen input and VGA output on Basys3.

EMNIST NPU, VGA, TFT-LCD를 각각 AXI Custom IP로 패키징해 Vivado Block Design에 연결하고, MicroBlaze에서 Vitis C 코드로 암호화 로직과 UI를 제어하는 시스템.

**역할 분리:**

- **RTL (Custom IP)**: NPU 추론, VGA 신호 생성, ILI9341/XPT2046 SPI 제어
- **C 소프트웨어 (Vitis)**: 카이사르 암호화/복호화, 화면 구성, 버튼/스위치 처리, 모드 제어

## 현재 진행 상태 (2026-06-30 기준)

## 2026-06-30 TOP/Vitis Integration Status Update

현재 TOP Vivado Block Design과 Vitis 연결성 검증까지 진행됐다. IP_TEST 단독 RTL 검증 이후, TOP 프로젝트에서 MicroBlaze V(RISC-V), NPU/TFT/VGA AXI Custom IP, UARTLite, local memory를 통합했고 Vitis bare-metal 애플리케이션에서 AXI 접근을 확인했다.

### 완료된 통합 작업

- `Vivado/TOP/HandCipher` Block Design 구성 및 XSA export 진행
- MicroBlaze V local memory를 128KB로 확장
  - Vitis `lscript.ld`: `lmb_bram_0 : ORIGIN = 0x0, LENGTH = 0x20000`
  - `xparameters.h`: `XPAR_LMB_BRAM_0_BASEADDRESS 0x0`, `HIGHADDRESS 0x1ffff`
- AXI 주소 재배치 및 Vitis platform 반영
  - NPU: `0x0002_0000 ~ 0x0002_0FFF`
  - VGA: `0x0002_1000 ~ 0x0002_1FFF`
  - TFT-LCD: `0x0003_0000 ~ 0x0003_0FFF`
  - UARTLite: `0x4060_0000 ~ 0x4060_FFFF`
- `Vitis/HandCipher/src/helloworld.c`를 자동 연결성 테스트 앱으로 변경
  - NPU CTRL readback 확인
  - TFT CTRL enable 및 STATUS read 확인
  - VGA CTRL enable, CANVAS_MODE readback, 문자 버퍼/캔버스 write smoke test 수행

### 최종 UART 연결성 검증 결과

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

판정: MicroBlaze에서 NPU/TFT/VGA AXI slave까지의 주소 매핑과 기본 레지스터 접근은 정상이다. TFT/VGA의 실제 화면 경로도 사용자가 보드에서 확인했다.

### 현재 남은 주요 작업

- Vitis 테스트 앱을 최종 HandCipher 앱으로 확장
  - TFT OK/CLEAR 또는 보드 버튼 입력 처리
  - NPU start/status/result 플로우 연결
  - VGA UI 화면 구성 및 카이사르 암호화/복호화 버퍼 관리
- RTL NPU 정확도 문제는 별도 보류
  - 학습/export 데이터 자체는 정상이나, RTL NPU는 시뮬레이션에서 Python 정수 모델과 결과가 맞지 않았음
  - 최종 데모 신뢰성을 위해 필요하면 Vitis 소프트웨어 추론 또는 RTL NPU 타이밍 수정 중 하나를 선택해야 함

---

현재 저장소 기준으로 **Phase 1 학습 파이프라인**, **Phase 2 IP_TEST RTL 구현/시뮬레이션 검증**, 그리고 **TOP/Vitis 기본 AXI 연결성 검증**까지 완료 상태다.

- 완료:
  - EMNIST 학습/양자화/export 및 정수 정확도 검증
  - `npu_ctrl.v`, `npu_axi.v`, weight/bias ROM, `tb_npu.v`, `tb_npu_axi.v`
  - `canvas_display.v`, `draw_canvas.v`, `tft_axi.v`, `tb_tft.v`
  - `font_rom.v`, `vga_ctrl.v`, `vga_axi.v`, `tb_font_rom.v`, `tb_vga.v`, `tb_vga_axi.v`
  - `Vivado/IP_TEST/IP_TEST.xpr`에 주요 RTL/시뮬레이션 파일 등록
- 미완료/확인 필요:
  - TOP/Vitis 기본 AXI 연결성은 통과했지만 최종 HandCipher 앱 로직은 아직 테스트 앱 수준
  - NPU RTL 결과가 Python 정수 모델과 불일치하는 문제는 보류 상태
  - TFT 터치 좌표/OK/CLEAR sticky flag의 XPT2046 bitstream 기반 시뮬레이션 보강은 남아 있음
  - 최종 UI/카이사르 암호화/복호화 Vitis 앱 구현 및 보드 검증 필요

**시스템 흐름:**

```
[DRAWING]    글자 그리기 (TFT 캔버스)
     ↓ OK (btnC 또는 터치 OK버튼)
[INFERRING]  NPU 추론 실행 → MicroBlaze가 캔버스 픽셀 784개를 TFT IP에서 읽어 VGA IP에 전달
     ↓ done (~157μs)
[CONFIRMING] VGA에 손글씨 프리뷰 + "NPU Result: X" + btnC=CONFIRM / btnL=RETRY 표시
             TFT 캔버스는 그대로 유지
     ↓ btnC/터치OK=확인        ↓ btnL/터치CLEAR=재시도
[CONFIRMED]                  [DRAWING으로 복귀 + 캔버스 CLEAR]
  Caesar 암호화 → VGA 버퍼 추가
  캔버스 CLEAR → 다음 글자 대기

[복호화] SW[14]=1 → 버퍼 내 암호문 C코드 역변환 → VGA IP 출력
```

---

## 하드웨어 구성

| 하드웨어                 | 역할                                          |
| ------------------------ | --------------------------------------------- |
| ILI9341 (240×320, PMOD) | 글자 그리기 캔버스 + 터치 버튼 UI            |
| XPT2046 (PMOD 공유)      | 터치 좌표 입력                                |
| VGA 모니터 (640×480)    | 텍스트/결과 출력                              |
| btnC                     | OK (NPU 추론 트리거) — 터치 OK버튼과 동일    |
| btnL                     | CLEAR (캔버스 초기화) — 터치 CLEAR버튼과 동일|
| btnR                     | 버퍼 초기화                                   |
| SW[4:0]                  | 카이사르 시프트 값 (0~25)                     |
| SW[14]                   | 0=암호화, 1=복호화                            |
| SW[15]                   | 전체 리셋                                     |

**TFT LCD 화면 레이아웃 (240×320 portrait):**

```
+------------ 240px ------------+
|                               |
|      캔버스 영역 (240×240)    |  y: 0~239
|   (28×28 그리드, 셀당 8px)   |
|                               |
+-------------------------------+  y: 240
|  [    OK    ] | [  CLEAR  ]  |  y: 240~319 (80px)
|   (녹색)        (빨간색)      |
+-------------------------------+
```

터치 좌표 y ≥ 240이면 그리기 대신 버튼 판정:
- x < 120 → OK 트리거 (STATUS[2] 세팅)
- x ≥ 120 → CLEAR 트리거 (STATUS[3] 세팅)

---

## Block Design 구성 (Vivado)

```
┌─────────────────────────────────────────────────────┐
│                  AXI Interconnect                    │
│                                                     │
│  MicroBlaze ──┬──► NPU IP      (0x0002_0000)       │
│  (128KB LMB)  ├──► VGA IP      (0x0002_1000)       │
│               ├──► TFT-LCD IP  (0x0003_0000)       │
│               └──► UARTLite    (0x4060_0000)       │
│                    (buttons + switches)              │
└─────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│  캔버스 BRAM (Block Design 레벨, BRAM Generator IP)              │
│                                                                  │
│  TFT-LCD IP ──► bram_porta (write: 터치 픽셀 1-bit, addr 0~783) │
│  NPU IP     ◄── bram_portb (read:  추론 시 픽셀 순차 읽기)      │
│                                                                  │
│  → MicroBlaze는 NPU_CTRL=1만 쓰면 됨 (784바이트 전송 불필요)    │
│  → BRAM은 두 IP 사이의 공유 하드웨어로 Block Design에서 배선    │
└──────────────────────────────────────────────────────────────────┘
```

---

## BRAM 리소스 (Artix-7 35T: BRAM18 100개)

| 내용                          | BRAM18             |
| ----------------------------- | ------------------ |
| MicroBlaze local memory (128KB) | 64                 |
| NPU L1 weight ROM (784×64)   | 25                 |
| NPU L2 weight ROM (64×26)    | 1                  |
| 캔버스 BRAM (28×28, 공유)    | 1                  |
| VGA 문자 버퍼 (40×30)        | 1                  |
| VGA 폰트 ROM (16×16 × 128)  | 2                  |
| **합계(추정)**                | **94 / 100** |

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
│   │   │       ├── npu_ctrl.v             (✅ EMNIST 추론 FSM)
│   │   │       ├── weight_rom_l1.v        (✅ training/exported/*.mem 사용)
│   │   │       ├── weight_rom_l2.v        (✅ training/exported/*.mem 사용)
│   │   │       ├── bias_rom_l1.v          (✅ training/exported/*.mem 사용)
│   │   │       ├── bias_rom_l2.v          (✅ training/exported/*.mem 사용)
│   │   │       ├── npu_axi.v              (✅ NPU AXI4-Lite 래퍼)
│   │   │       ├── canvas_display.v       (✅ ILI9341 SPI 스트리밍)
│   │   │       ├── draw_canvas.v          (✅ 터치 좌표 → BRAM Port A)
│   │   │       ├── tft_axi.v              (✅ TFT AXI4-Lite 래퍼)
│   │   │       ├── font_rom.v             (✅ 16×16 폰트 ROM)
│   │   │       ├── vga_ctrl.v             (✅ 640×480 타이밍 + 문자 렌더러)
│   │   │       └── vga_axi.v              (✅ VGA AXI4-Lite 래퍼)
│   │   ├── IP_TEST.srcs/sim_1/new/
│   │   │   ├── tb_font_rom.v              (✅ XSim PASS)
│   │   │   ├── tb_npu.v                   (✅ XSim PASS)
│   │   │   ├── tb_npu_axi.v               (✅ XSim PASS)
│   │   │   ├── tb_tft.v                   (✅ XSim PASS)
│   │   │   ├── tb_vga.v                   (✅ XSim PASS)
│   │   │   └── tb_vga_axi.v               (✅ XSim PASS)
│   │   └── IP_TEST.srcs/constrs_1/
│   │       └── imports/Basys-3-Master.xdc
│   │
│   └── TOP/                               ← Vivado 프로젝트 #2 (통합 + .xsa 생성)
│       └── HandCipher/                    (✅ Block Design/XSA 생성, AXI 연결성 검증)
│
├── Vitis/                                ← platform_HandCipher + HandCipher 테스트 앱 존재
└── training/
    ├── training_emnist.py                 (✅ 완료 → model.pth 생성됨)
    ├── quantize_export.py                 (✅ 완료 → exported/*.mem 4개 + npu_params.vh)
    ├── test_inference.py                  (✅ 완료 → 정수 정확도 87.74%)
    ├── gen_font_mem.py                    (✅ 16×16 font_rom.mem 생성)
    └── exported/                          (✅ weights/biases/font/npu_params 산출물)
```

---

## Part 1: 학습 파이프라인 ✅ 완료 (정수 정확도 87.74%)

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

**캔버스 BRAM 공유 (Option A — BRAM Generator 직접 공유):**

- BRAM은 `npu_ip` 내부가 아니라 **Block Design 레벨 BRAM Generator IP**로 존재
- IP_TEST 단계에서는 `image_buffer.v`(내부 dual-port BRAM)로 standalone 검증
- TOP Block Design 통합 시: `image_buffer.v`를 제거하고, 두 IP의 BRAM 포트를 외부 포트로 노출해 BRAM Generator에 연결
- Port A: `tft_ip`의 `draw_canvas`가 터치 픽셀 1-bit 쓰기 (`clka`, `addra`, `dina`, `wea`, `ena`)
- Port B: `npu_ctrl`이 순차 읽기 (1→0xFF, 0→0x00 변환 후 uint8 사용) (`clkb`, `addrb`, `doutb`, `enb`)

**`npu_axi.v` 추가 포트 (AXI4-Lite 슬레이브 외):**

```verilog
// 캔버스 BRAM Port B (Block Design에서 BRAM Generator Port B에 직결)
output [9:0]  canvas_addrb,
output        canvas_enb,
input         canvas_doutb,   // 1-bit

// NPU 결과
output [4:0]  letter,
output        done
```

---

### IP #2: `vga_ip` — VGA 문자 모드 디스플레이

**AXI 레지스터 맵:**

```
0x00: CTRL           [0]=enable, [1]=clear (전체 스페이스로 채움)
0x04: CHAR_ADDR      [10:0] 문자 버퍼 주소 (0~1199, 40×30)
0x08: CHAR_DATA      [7:0]  쓸 문자 ASCII
0x0C: WR_STRB        [0]=1 쓰기 실행 (자동 클리어)
0x10: FG_COLOR       [11:0] 전경색 RGB444
0x14: BG_COLOR       [11:0] 배경색 RGB444
0x18: CANVAS_WR_ADDR [9:0]  캔버스 프리뷰 버퍼 쓰기 주소 (0~783)
0x1C: CANVAS_WR_DATA [0]    캔버스 픽셀 값 (1=흰색, 0=검정)
0x20: CANVAS_WR_EN   [0]    1 펄스 → 버퍼에 기록 (자동 클리어)
0x24: CANVAS_MODE    [0]    0=일반 텍스트 모드, 1=CONFIRMING 프리뷰 모드
```

**`vga_axi.v` 동작:**

- 일반 모드 (CANVAS_MODE=0): CPU가 CHAR_ADDR/CHAR_DATA/WR_STRB로 문자 버퍼 기록 → 텍스트 출력
- 프리뷰 모드 (CANVAS_MODE=1): CPU가 CANVAS_WR_ADDR/DATA/EN으로 784픽셀 전송 → 손글씨 프리뷰 표시
- `vga_ctrl`이 두 모드를 합성해 픽셀 생성

**`vga_ctrl.v` (640×480 @ 60Hz, 16×16 폰트, 40×30 문자):**

- 픽셀 클록: 100MHz ÷ 4 = 25MHz (클록 enable 방식, 새 clock domain 생성 금지)
- `H_TOTAL=800, V_TOTAL=525` (표준 640×480 @ 60Hz 타이밍)
- 일반 모드: `char_buf[row*40+col]` → `font_rom[char*16+row_in]` → `pixel_on`
  - 16×16 폰트는 한 row가 16-bit이며, ASCII 0~127 전체 저장
  - addr = char_code × 16 + row_in_char
  - `gen_font_mem.py`로 16×16 `font_rom.mem` 생성 완료 (2048 lines, 4 hex digits/line)
- 프리뷰 모드 (x: 16~239, y: 48~271): `canvas_buf[py*28+px]` → 흰/검 8×8 블록 렌더링
  - `px = (vga_x - 16) / 8` (0~27), `py = (vga_y - 48) / 8` (0~27)
  - 나머지 영역은 텍스트 그대로 유지 (인식 결과, 안내 문구)

**`canvas_buf` (VGA IP 내부, distributed RAM):**

- 784비트 = 32비트 레지스터 25개 → **BRAM 불필요 (LUT 기반)**
- CANVAS_WR_EN 펄스로 1비트씩 기록, vga_ctrl이 픽셀 클록에 동기로 읽기

**CONFIRMING 상태 VGA 화면 (CANVAS_MODE=1):**

```
+-------------------- 640px ---------------------+
| === CAESAR CIPHER SYSTEM ===                   | row 0
| MODE: ENCRYPT   SHIFT: +3                      | row 2
|                                                |
| +----------+   NPU Result : B                 | row 5
| |          |                                  |
| | 28×28    |   btnC = CONFIRM                 | row 8
| | 손글씨   |   btnL = RETRY                   | row 10
| | 프리뷰   |                                  |
| | (224×224)|                                  |
| +----------+                                  | row 17
|                                                |
| Plaintext  : APPLE                             | row 22
| Ciphertext : DSSOH                             | row 23
|                                                |
| C=OK L=CLR SW=SHIFT MODE                       | row 29
+------------------------------------------------+
```

---

### IP #3: `tft_ip` — ILI9341 캔버스 + XPT2046 터치

**AXI 레지스터 맵:**

```
0x00: CTRL           [0]=enable, [1]=clear_canvas
0x04: TOUCH_X        [11:0] raw ADC X (읽기 전용)
0x08: TOUCH_Y        [11:0] raw ADC Y (읽기 전용)
0x0C: STATUS         [0]=touch_valid (캔버스 영역 터치 중)
                     [1]=lcd_ready
                     [2]=btn_ok    (터치 OK버튼 — sticky, 읽으면 자동 클리어)
                     [3]=btn_clear (터치 CLEAR버튼 — sticky, 읽으면 자동 클리어)
0x10: CANVAS_RD_ADDR [9:0]  캔버스 픽셀 읽기 주소 (0~783), CPU가 씀
0x14: CANVAS_RD_DATA [0]    해당 주소 픽셀 값, CPU가 읽음 (1클록 지연)
```

**`tft_axi.v` 동작:**

- `xpt2046`가 터치 감지 → 좌표 y < 240이면 캔버스 BRAM 쓰기, STATUS[0]=1
- 좌표 y ≥ 240, x < 120 → STATUS[2](btn_ok) 세팅
- 좌표 y ≥ 240, x ≥ 120 → STATUS[3](btn_clear) 세팅
- `canvas_display`가 캔버스 BRAM + 버튼 영역 렌더링 → ILI9341 SPI 스트리밍
- CTRL[1]=1 또는 btn_clear → 캔버스 BRAM 전체 0으로 초기화

**`canvas_display.v` 렌더링:**

- y < 240: 캔버스 영역 — BRAM 읽어 흰/검 픽셀 출력 (셀당 8px, 28×8=224, 중앙 정렬)
- y ≥ 240, x < 120: OK 버튼 — 녹색 배경 + "OK" 텍스트
- y ≥ 240, x ≥ 120: CLEAR 버튼 — 빨간색 배경 + "CLR" 텍스트

**캔버스 BRAM Port A (최종 TOP Block Design 공유 BRAM):**

- `tft_ip`는 캔버스 BRAM을 최종 IP 내부에 소유하지 않음
- `draw_canvas` → 외부 BRAM Generator Port A 구동 (1-bit write, addr = row×28+col)
- `npu_ip`는 같은 BRAM Generator의 Port B를 읽어서 28×28 픽셀을 추론 입력으로 사용
- MicroBlaze는 캔버스 픽셀 784개를 복사하지 않고, `NPU_CTRL.start`만 써서 추론 시작
- `xpt2046` 모듈: `tft_lcd_sv.sv`에서 그대로 재사용, 50MHz 공급 (100MHz ÷ 2)

**`tft_axi.v` 추가 포트 (AXI4-Lite 슬레이브 외):**

```verilog
// 캔버스 BRAM Port A (Block Design에서 BRAM Generator Port A에 직결)
output [9:0]  canvas_addra,
output        canvas_dina,    // 1-bit
output        canvas_wea,
output        canvas_ena
```

- IP_TEST standalone 검증에서는 `image_buffer.v`를 내부 dual-port BRAM처럼 사용
- TOP Block Design 통합에서는 `image_buffer.v`를 제거하고, 위 포트를 외부로 노출해 BRAM Generator Port A에 배선
- 현재 `tft_axi.v`는 LCD 표시와 CPU `CANVAS_RD_DATA` readback을 위해 내부 784-bit canvas mirror를 유지하고, 같은 write/clear 스트림을 외부 BRAM Port A에도 내보낸다. 따라서 NPU는 외부 BRAM을 읽고, TFT 표시/CPU readback은 내부 mirror를 읽는다.

---

## Part 3: Vitis C 소프트웨어

### `main.c`

```c
#include "xparameters.h"
#include "xgpio.h"
#include "caesar.h"
#include "display.h"

#define NPU_BASE   XPAR_NPU_IP_0_BASEADDR
#define VGA_BASE   XPAR_VGA_IP_0_BASEADDR
#define TFT_BASE   XPAR_TFT_IP_0_BASEADDR

#define NPU_CTRL         (NPU_BASE + 0x00)
#define NPU_STATUS       (NPU_BASE + 0x04)
#define NPU_RESULT       (NPU_BASE + 0x08)
#define TFT_STATUS       (TFT_BASE + 0x0C)
#define TFT_CANVAS_ADDR  (TFT_BASE + 0x10)
#define TFT_CANVAS_DATA  (TFT_BASE + 0x14)
#define VGA_CANVAS_ADDR  (VGA_BASE + 0x18)
#define VGA_CANVAS_DATA  (VGA_BASE + 0x1C)
#define VGA_CANVAS_EN    (VGA_BASE + 0x20)
#define VGA_CANVAS_MODE  (VGA_BASE + 0x24)

// AXI GPIO 비트마스크 (채널 1: 버튼)
// reset_p(U18)=center, btnL(W19), btnR(T17) — GPIO 비트 위치는 XDC 순서와 일치
#define BTN_C  0x01   // center (reset_p)
#define BTN_L  0x02   // left
#define BTN_R  0x04   // right

typedef enum { DRAWING, CONFIRMING } State;

char plain_buf[64]  = {0};
char cipher_buf[64] = {0};
int  buf_len = 0;

// NPU 추론 후 캔버스 픽셀 784개를 TFT IP에서 읽어 VGA IP에 전송
void transfer_canvas_to_vga() {
    for (int i = 0; i < 784; i++) {
        Xil_Out32(TFT_CANVAS_ADDR, i);
        u32 px = Xil_In32(TFT_CANVAS_DATA) & 0x1;
        Xil_Out32(VGA_CANVAS_ADDR, i);
        Xil_Out32(VGA_CANVAS_DATA, px);
        Xil_Out32(VGA_CANVAS_EN, 1);
    }
}

int main() {
    XGpio gpio;
    XGpio_Initialize(&gpio, XPAR_AXI_GPIO_0_DEVICE_ID);

    State state = DRAWING;
    char inferred_char = '?';
    display_drawing(VGA_BASE, plain_buf, cipher_buf, buf_len, 0, 0);

    while (1) {
        u32 sw  = XGpio_DiscreteRead(&gpio, 2);
        u32 btn = XGpio_DiscreteRead(&gpio, 1);
        int shift = sw & 0x1F;
        int mode  = (sw >> 14) & 0x1;

        u32 tft_st    = Xil_In32(TFT_STATUS);
        int touch_ok    = (tft_st >> 2) & 0x1;
        int touch_clear = (tft_st >> 3) & 0x1;

        if (state == DRAWING) {
            if ((btn & BTN_C) || touch_ok) {
                // NPU 추론
                Xil_Out32(NPU_CTRL, 1);
                while (!(Xil_In32(NPU_STATUS) & 0x1));
                inferred_char = 'A' + (Xil_In32(NPU_RESULT) & 0x1F);

                // 캔버스 픽셀 VGA로 전송 후 프리뷰 모드 진입
                transfer_canvas_to_vga();
                Xil_Out32(VGA_CANVAS_MODE, 1);
                display_confirming(VGA_BASE, inferred_char, shift, mode,
                                   plain_buf, cipher_buf, buf_len);
                state = CONFIRMING;
            }
            if ((btn & BTN_L) || touch_clear)
                Xil_Out32(TFT_BASE + 0x00, 0x2);  // 캔버스 CLEAR

            if (btn & BTN_R) {
                buf_len = 0;
                display_drawing(VGA_BASE, plain_buf, cipher_buf, buf_len, shift, mode);
            }

        } else {  // CONFIRMING
            if ((btn & BTN_C) || touch_ok) {
                // 확인: 암호화 후 버퍼에 추가
                char cipher_c = mode ? caesar_decode(inferred_char, shift)
                                     : caesar_encode(inferred_char, shift);
                if (buf_len < 64) {
                    plain_buf[buf_len]  = inferred_char;
                    cipher_buf[buf_len] = cipher_c;
                    buf_len++;
                }
                Xil_Out32(VGA_CANVAS_MODE, 0);
                Xil_Out32(TFT_BASE + 0x00, 0x2);  // 캔버스 CLEAR
                display_drawing(VGA_BASE, plain_buf, cipher_buf, buf_len, shift, mode);
                state = DRAWING;

            } else if ((btn & BTN_L) || touch_clear) {
                // 재시도: 캔버스 지우고 다시 그리기
                Xil_Out32(VGA_CANVAS_MODE, 0);
                Xil_Out32(TFT_BASE + 0x00, 0x2);
                display_drawing(VGA_BASE, plain_buf, cipher_buf, buf_len, shift, mode);
                state = DRAWING;
            }
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
// 기본 출력
void vga_putchar(u32 base, int row, int col, char c, u32 fg, u32 bg);
void vga_puts(u32 base, int row, int col, const char *str, u32 fg, u32 bg);
void vga_clear(u32 base);

// DRAWING 상태 화면 (일반 텍스트 모드)
void display_drawing(u32 base, char *plain, char *cipher,
                     int len, int shift, int mode) {
    char line[82];
    vga_clear(base);
    vga_puts(base, 0, 20, "=== CAESAR CIPHER SYSTEM ===", WHITE, DARK_BLUE);
    sprintf(line, "MODE: %-9s  SHIFT: +%d",
            mode ? "DECRYPT" : "ENCRYPT", shift);
    vga_puts(base, 2, 0, line, CYAN, BLACK);

    plain[len] = '\0'; cipher[len] = '\0';
    sprintf(line, "Plaintext  : %-64s", plain);
    vga_puts(base, 36, 0, line, GREEN, BLACK);
    sprintf(line, "Ciphertext : %-64s", cipher);
    vga_puts(base, 37, 0, line, CYAN, BLACK);

    vga_puts(base, 58, 0,
             "btnC=OK  btnL=CLR  btnR=BUF_CLR  SW[4:0]=SHIFT  SW[14]=MODE",
             GRAY, BLACK);
}

// CONFIRMING 상태 화면 (캔버스 프리뷰 모드, CANVAS_MODE=1)
// canvas_buf는 VGA IP가 직접 렌더링, 여기서는 텍스트 영역만 기록
void display_confirming(u32 base, char inferred, int shift, int mode,
                        char *plain, char *cipher, int len) {
    char line[82];
    // 헤더/모드는 그대로 유지
    sprintf(line, "NPU Result : %c", inferred);
    vga_puts(base, 6, 30, line, YELLOW, BLACK);
    vga_puts(base, 10, 30, "Press btnC = CONFIRM", GREEN, BLACK);
    vga_puts(base, 12, 30, "Press btnL = RETRY",  RED,   BLACK);

    plain[len] = '\0'; cipher[len] = '\0';
    sprintf(line, "Plaintext  : %-40s", plain);
    vga_puts(base, 36, 0, line, GREEN, BLACK);
    sprintf(line, "Ciphertext : %-40s", cipher);
    vga_puts(base, 37, 0, line, CYAN, BLACK);
}
```

---

## Part 4: 테스트벤치

### `tb_npu.v`

- AXI write CTRL=1 → 추론 시작
- STATUS done 확인, RESULT 0~25 범위 검증
- CANVAS_RD_ADDR/DATA 레지스터로 캔버스 픽셀 읽기 확인

### `tb_vga.v`

- AXI로 문자 기록 후 VGA 픽셀 스트림 검증
- Hsync/Vsync 주기 확인 (640×480 @ 60Hz)
- CANVAS_MODE=1 전환 후 canvas_buf 픽셀 렌더링 확인

### `tb_tft.v`

- AXI write CTRL[1]=1 → canvas clear sequence 시작 확인
- clear 중 외부 BRAM Port A write가 0으로 발생하는지 확인
- CANVAS_RD_ADDR/DATA readback 확인
- STATUS[1]=lcd_ready 확인
- 다음 보강: XPT2046 DOUT bitstream 모델링 후 OK/CLEAR sticky flag와 터치 좌표 변환 검증

---

## 구현 순서

### Phase 1 — 학습 (PC) ✅ 완료

1. ~~`training_emnist.py` → model.pth~~ ✅
2. ~~`quantize_export.py` → .mem 4개 + npu_params.vh~~ ✅ (SHIFT_L1=10)
3. ~~`test_inference.py` → 정수 시뮬레이션 정확도~~ ✅ **87.74%** (목표 ≥80%)

### Phase 2 — IP RTL 구현 및 검증 (Vivado/IP_TEST/)

**NPU IP:**

4. ~~`npu_ctrl.v`, `weight_rom_l1.v`, `weight_rom_l2.v`, `bias_rom_l1.v`, `bias_rom_l2.v`~~ ✅
5. ~~`npu_axi.v` (AXI4-Lite 래퍼, 외부 Canvas BRAM Port B)~~ ✅
6. ~~`tb_npu.v` → XSim: start → done, RESULT 0~25 확인~~ ✅
6-1. ~~`tb_npu_axi.v` → 실제 AXI write/read polling 검증, STATUS done sticky 확인~~ ✅
7. **Create and Package New IP** → `npu_ip_v1_0` ⚠️ 패키징 산출물 저장소 누락/확인 필요

**TFT-LCD IP:**

8. ~~`canvas_display.v`, `draw_canvas.v` (tft_lcd_sv.sv의 spi/xpt2046 재사용)~~ ✅
9. ~~`tft_axi.v` (AXI4-Lite 래퍼)~~ ✅
10. ~~`tb_tft.v` → XSim: AXI clear/readback + BRAM Port A write 확인~~ ✅
11. **Create and Package New IP** → `tft_ip_v1_0` ⏳ 미완료

**VGA IP:**

12. ~~`training/gen_font_mem.py` 수정 → 16×16 `font_rom.mem` 재생성~~ ✅
13. ~~`font_rom.v` 수정 → 16-bit row, 2048-depth ROM (128 chars × 16 rows)~~ ✅
14. ~~`tb_font_rom.v` 갱신 → 16×16 폰트 ROM 검증~~ ✅
15. ~~`vga_ctrl.v` 수정 → 40×30 문자, `char*16+row`, 16-bit row 렌더러~~ ✅
16. ~~`tb_vga.v` 갱신 → 16×16 문자 출력 + Hsync/Vsync 검증~~ ✅
17. ~~`vga_axi.v` 작성 → AXI4-Lite VGA 래퍼, CHAR_ADDR 0~1199 기준~~ ✅
17-1. ~~`tb_vga_axi.v` → AXI 문자쓰기/clear/canvas_mode/Hsync 검증~~ ✅
18. **Create and Package New IP** → `vga_ip_v1_0` ⏳ 미완료

### Phase 3 — TOP 통합 (Vivado/TOP/) ✅ 기본 연결성 완료

19. TOP 프로젝트 생성, IP Repository에 npu_ip / tft_ip / vga_ip 추가
20. Block Design 생성:
    - MicroBlaze V local memory (128KB LMB)
    - AXI Interconnect
    - npu_ip, tft_ip, vga_ip 각각 Add IP
    - AXI GPIO (버튼 + 스위치)
    - **BRAM Generator** Add IP:
      - Memory Type: True Dual Port RAM
      - Width: 1bit, Depth: 1024 (≥784)
      - Port A: `tft_ip`의 `canvas_addra/dina/wea/ena`에 배선
      - Port B: `npu_ip`의 `canvas_addrb/enb/doutb`에 배선
      - 두 포트 클럭 모두 시스템 100MHz 클럭 연결
21. `basys3.xdc` 핀 제약 추가
22. 합성 + 구현 → BRAM18 ≤50, WNS ≥ 0 확인
23. **File → Export → Export Hardware** → `handcipher.xsa` 생성

### Phase 4 — Vitis C 코드 (Vitis/) ⏳ 미시작

24. Vitis에서 handcipher.xsa로 Platform 프로젝트 생성
25. Application 프로젝트 생성 → `caesar.c` / `caesar.h`
26. `display.c` / `display.h`
27. `main.c`
28. 빌드 + Basys3에 Program Device

### Phase 5 — 하드웨어 검증 ⏳ 미시작

29. 글자 그리기 → btnC → VGA 암호화 결과 확인
30. SW[14]=1 복호화 모드 전환 확인
31. SW[4:0] 시프트 값 변경 실시간 반영 확인

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
| BRAM        | 31 / 100         | 46 / 100                |
| Vivado 작업 | RTL only         | RTL + Block Design      |
| Vitis 작업  | 없음             | C 코드 작성             |

---

## 미해결 이슈

### NPU IP 패키징 파일 누락 의심 (2026-06-29)

- `kwakyj91(곽영재)`가 로컬 Vivado에서 `npu_ip_v1_0` 패키징을 완료했다고 PLAN.md에 기록했으나, git 저장소에 IP 파일이 없음.
- **원인 추정:** `Vivado/TOP/.gitignore`에 `*.xml` 규칙이 있어서 `component.xml`(IP 패키징의 핵심 파일)이 커밋되지 않았을 가능성이 높음.
- **확인 필요:** 곽영재 로컬에 `ip_repo/npu_ip_v1_0/component.xml`이 존재하는지 확인.
- **조치 필요 시:** `.gitignore`에서 IP repo 경로 예외 처리 후 재업로드.
  ```
  *.xml
  !**/ip_repo/**/component.xml
  ```

---

## 작업 기록

### 2026-06-26 (목)

| 시각 | 커밋 | 내용 |
|------|------|------|
| 14:37 | `00e1f65` | **프로젝트 초기화** — 폴더 구조 생성, PLAN.md 초안 작성 |
| 15:02 | `bf2c48c` | **PLAN.md 수정** — 설계 방향 조정 |
| 16:25 | `4d67a21` | **`training_emnist.py` 작성** — EMNIST Letters 학습, model.pth 생성 (float 정확도 확인) |
| 17:23 | `a940434` | **`quantize_export.py` / `test_inference.py` 작성** — 고정소수점 양자화, .mem 4개 + npu_params.vh 생성, 정수 정확도 **87.74%** 확인 |

### 2026-06-27 (금)

| 시각 | 커밋 | 내용 |
|------|------|------|
| 14:52 | `0f748bc` | **폴더 구조 정리** — Vivado 프로젝트 디렉토리 재배치 |
| 15:34 | `d899f8a` | **IP_TEST 업로드** — TFT LCD 캔버스/터치 검증용 초기 파일 업로드 |
| 16:42 | `15b40aa` | **가중치 .mem 파일 추가 + 터치 노이즈 문서화** — `weights_l1/l2.mem`, `biases_l1/l2.mem` 추가, XPT2046 노이즈 이슈 PLAN.md에 정리 |
| 16:49 | `d3e9d18` | **PLAN.md 조정** — TFT IP 설계 사양 보완 |

### 2026-06-28 (토)

| 시각 | 커밋 | 내용 |
|------|------|------|
| 14:41 | `26653cc` | **TFT 타이밍 오류 수정 + `font_rom.v` 작성** — LCD SPI 속도 25MHz로 낮춰 화면 노이즈 개선, 8×8 폰트 ROM 초안 작성 |
| 16:03 | `9a225f0` | **`font_rom.mem` 생성 + `tb_font_rom.v` 작성** — gen_font_mem.py로 mem 파일 생성, 폰트 ROM 테스트벤치 XSim 검증 |
| 16:57 | `20d2883` | **`vga_ctrl.v` 수정** — 640×480 @60Hz 타이밍, 16×16 폰트 기준 40×30 문자 렌더러 구현 |

### 2026-06-29 (일)

| 시각 | 커밋 | 내용 |
|------|------|------|
| 09:51 | `21fb4b1` | **`requirements.txt` 추가** — 학습 환경 패키지 목록 정리 |
| 10:34 | `e300fc9` | **`IP_TEST.xpr` 수정** — Vivado 프로젝트 파일 XML 오류 복구 (`font_rom.v` `</File>` 누락 태그 복원) |
| 12:36 | `8f7321b` | **NPU IP RTL 작성** — `npu_ctrl.v`, `npu_axi.v`, `weight_rom_l1/l2.v`, `bias_rom_l1/l2.v`, `tb_npu.v` 작성, XSim 검증 (157μs 추론 타이밍 확인) |
| 12:42 | `f00aa65` | **NPU IP 패키징 완료** — PLAN.md에 NPU 파트 완료 기록, `npu_ip_v1_0` 패키지 생성 |
| 12:54 | `0f3c3a4` | **VGA IP 완성** — `vga_axi.v` 작성, `tb_vga.v` 갱신, 16×16 폰트 전환 전면 적용, .gitignore 추가, XSim `PASS: tb_vga completed` 확인, 보드 테스트 정상 |
| 12:58 | `c12b318` | **Merge** — NPU 파트(원격 브랜치) merge |
| 14:20 | `f386d2b` | **PLAN.md 최종 정리** — NPU 파트 상세 사양 및 검증 결과 반영 |
| 16:09 | `working tree` | **TFT IP 1차 구현** — `canvas_display.v`, `draw_canvas.v`, `tft_axi.v`, `tb_tft.v` 작성, `tft_lcd_sv.sv` 재사용 활성화, XSim `PASS: tb_tft completed` 확인 |
| 17:07 | `working tree` | **AXI 테스트벤치 추가** — `tb_npu_axi.v`, `tb_vga_axi.v` 작성, `npu_axi` STATUS done sticky 및 WSTRB 폭 수정, XSim PASS 확인 |

### 2026-06-30 (화)

| 시각 | 커밋 | 내용 |
|------|------|------|
| working tree | `working tree` | **현재 상태 재점검** — Phase 2 IP_TEST RTL/AXI 테스트 완료 상태 확인, IP 패키징/TOP/Vitis 미구현 상태 PLAN.md에 반영 |

---

**현재 VGA 관련 파일 상태 (2026-06-29 12:54 기준):**
- `training/gen_font_mem.py`: 16×16 ASCII font mem 생성
- `font_rom.mem`: 2048 lines, 4 hex digits/line
- `font_rom.v`: 11-bit addr, 16-bit data, 2048-depth ROM
- `vga_ctrl.v`: 640×480 @60Hz, 40×30 text, 16×16 font render, 28×28 preview
- `vga_axi.v`: AXI4-Lite 래퍼, CHAR_ADDR 0~1199, CANVAS_WR_*, FG/BG_COLOR
- `vga_test_top.v`: CONFIRMING 화면 standalone VGA test top
- `tb_font_rom.v`, `tb_vga.v`: 16×16 기준 XSim 검증 완료

---

**현재 TFT 관련 파일 상태 (2026-06-29 16:09 기준):**
- `canvas_display.v`: 240×320 portrait TFT 렌더링, 28×28 캔버스 8배 확대 표시, 하단 OK/CLR 버튼 표시
- `draw_canvas.v`: XPT2046 raw 좌표 변환, 좌우 반전 보정, 캔버스 영역 write, OK/CLEAR 버튼 판정, clear sequence 생성
- `tft_axi.v`: AXI4-Lite 래퍼, CTRL/TOUCH_X/TOUCH_Y/STATUS/CANVAS_RD_* 레지스터 구현
- `tft_axi.v`는 IP_TEST standalone 표시와 CPU readback을 위해 내부 784-bit canvas mirror를 유지하고, 같은 write/clear 스트림을 외부 `canvas_addra/dina/wea/ena`로도 출력
- `tft_lcd_sv.sv`: 기존 `spi`, `tft_sv`, `xpt2046` 재사용. LCD SPI 25MHz 완화 설정과 XPT2046 15ms 샘플링 설정 유지
- `tb_tft.v`: AXI `CTRL[1]` clear, 외부 BRAM Port A write, `CANVAS_RD_DATA`, `STATUS[1]=lcd_ready` 기본 검증
- 검증 결과: `xvlog -sv` 통과, `xelab tb_tft` 통과, XSim `PASS: tb_tft completed` 확인
- 남은 보강: XPT2046 `DOUT` bitstream 모델링 기반 터치 좌표/OK/CLEAR sticky flag 시뮬레이션

---

## basys3.xdc (주요 핀)

IP_TEST 프로젝트의 실제 핀 배치 기준. TFT는 PMOD JB, 터치는 PMOD JC 사용.

```tcl
## Clock
set_property -dict { PACKAGE_PIN W5   IOSTANDARD LVCMOS33 } [get_ports clk]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]

## Buttons
set_property -dict { PACKAGE_PIN U18  IOSTANDARD LVCMOS33 } [get_ports reset_p]  ;# Center = OK / CONFIRM
set_property -dict { PACKAGE_PIN T18  IOSTANDARD LVCMOS33 } [get_ports btnU]
set_property -dict { PACKAGE_PIN W19  IOSTANDARD LVCMOS33 } [get_ports btnL]     ;# Left = CLEAR / RETRY
set_property -dict { PACKAGE_PIN T17  IOSTANDARD LVCMOS33 } [get_ports btnR]     ;# Right = 버퍼 초기화
set_property -dict { PACKAGE_PIN U17  IOSTANDARD LVCMOS33 } [get_ports btnD]

## Switches  (SW[4:0]=shift, SW[14]=mode, SW[15]=reset)
set_property -dict { PACKAGE_PIN V17  IOSTANDARD LVCMOS33 } [get_ports {sw[0]}]
set_property -dict { PACKAGE_PIN V16  IOSTANDARD LVCMOS33 } [get_ports {sw[1]}]
set_property -dict { PACKAGE_PIN W16  IOSTANDARD LVCMOS33 } [get_ports {sw[2]}]
set_property -dict { PACKAGE_PIN W17  IOSTANDARD LVCMOS33 } [get_ports {sw[3]}]
set_property -dict { PACKAGE_PIN W15  IOSTANDARD LVCMOS33 } [get_ports {sw[4]}]
set_property -dict { PACKAGE_PIN T1   IOSTANDARD LVCMOS33 } [get_ports {sw[14]}]
set_property -dict { PACKAGE_PIN R2   IOSTANDARD LVCMOS33 } [get_ports {sw[15]}]

## VGA
set_property -dict { PACKAGE_PIN G19  IOSTANDARD LVCMOS33 } [get_ports {vgaRed[0]}]
set_property -dict { PACKAGE_PIN H19  IOSTANDARD LVCMOS33 } [get_ports {vgaRed[1]}]
set_property -dict { PACKAGE_PIN J19  IOSTANDARD LVCMOS33 } [get_ports {vgaRed[2]}]
set_property -dict { PACKAGE_PIN N19  IOSTANDARD LVCMOS33 } [get_ports {vgaRed[3]}]
set_property -dict { PACKAGE_PIN J17  IOSTANDARD LVCMOS33 } [get_ports {vgaGreen[0]}]
set_property -dict { PACKAGE_PIN H17  IOSTANDARD LVCMOS33 } [get_ports {vgaGreen[1]}]
set_property -dict { PACKAGE_PIN G17  IOSTANDARD LVCMOS33 } [get_ports {vgaGreen[2]}]
set_property -dict { PACKAGE_PIN D17  IOSTANDARD LVCMOS33 } [get_ports {vgaGreen[3]}]
set_property -dict { PACKAGE_PIN N18  IOSTANDARD LVCMOS33 } [get_ports {vgaBlue[0]}]
set_property -dict { PACKAGE_PIN L18  IOSTANDARD LVCMOS33 } [get_ports {vgaBlue[1]}]
set_property -dict { PACKAGE_PIN K18  IOSTANDARD LVCMOS33 } [get_ports {vgaBlue[2]}]
set_property -dict { PACKAGE_PIN J18  IOSTANDARD LVCMOS33 } [get_ports {vgaBlue[3]}]
set_property -dict { PACKAGE_PIN P19  IOSTANDARD LVCMOS33 } [get_ports Hsync]
set_property -dict { PACKAGE_PIN R19  IOSTANDARD LVCMOS33 } [get_ports Vsync]

## TFT LCD ILI9341 — PMOD JB
set_property -dict { PACKAGE_PIN A14  IOSTANDARD LVCMOS33 } [get_ports tft_cs]
set_property -dict { PACKAGE_PIN A16  IOSTANDARD LVCMOS33 } [get_ports tft_reset]
set_property -dict { PACKAGE_PIN B15  IOSTANDARD LVCMOS33 } [get_ports tft_dc]
set_property -dict { PACKAGE_PIN B16  IOSTANDARD LVCMOS33 } [get_ports tft_sdi]  ;# MOSI
set_property -dict { PACKAGE_PIN A15  IOSTANDARD LVCMOS33 } [get_ports tft_sck]
set_property -dict { PACKAGE_PIN A17  IOSTANDARD LVCMOS33 } [get_ports tft_sdo]  ;# MISO (미사용)

## XPT2046 Touch — PMOD JC
set_property -dict { PACKAGE_PIN K17  IOSTANDARD LVCMOS33 } [get_ports DCLK]
set_property -dict { PACKAGE_PIN M18  IOSTANDARD LVCMOS33 } [get_ports CS_N]
set_property -dict { PACKAGE_PIN N17  IOSTANDARD LVCMOS33 } [get_ports DIN]
set_property -dict { PACKAGE_PIN P18  IOSTANDARD LVCMOS33 } [get_ports DOUT]
set_property -dict { PACKAGE_PIN M19  IOSTANDARD LVCMOS33 PULLUP true } [get_ports PenIrq_n]

## Configuration
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
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

### 추가 TFT 수정 결과

IP_TEST에서 하단 버튼 UI와 LCD 표시 안정화를 추가로 검증했다.

#### 화면/터치 좌표 보정

- LCD 표시가 좌우 거울 반전처럼 보였으므로 표시용 x 좌표를 보정

```verilog
wire [7:0] lcd_px_raw = x[9:1];
wire [7:0] lcd_px = 8'd239 - lcd_px_raw;
```

- 표시 좌표를 반전한 뒤 터치 입력도 좌우 반대로 찍혀서, 터치 x 좌표도 같은 화면 좌표계로 보정

```verilog
wire [15:0] t_x_raw_clamped = (touch_x_raw > 239) ? 239 : touch_x_raw;
wire [15:0] t_x = 16'd239 - t_x_raw_clamped;
```

#### 하단 버튼 UI

- PLAN.md의 TFT 레이아웃대로 `y=240~319` 영역에 버튼 UI 추가
  - `x < 120`: OK 버튼
  - `x >= 120`: CLEAR 버튼
- 버튼 글자는 임시 도형 대신 5x7 블록 글자를 4배 확대한 형태로 렌더링
- CLEAR 버튼 터치 시 IP_TEST 내부에서 28x28 BRAM 전체를 0으로 초기화하는 동작 확인
- OK 버튼은 IP_TEST에서는 내부 sticky flag로만 보관하고, 실제 IP화 시 `STATUS[2]`에 연결 예정
- CLEAR 버튼은 실제 IP화 시 `STATUS[3]` 세팅과 `clear_canvas` 동작에 연결 예정

#### LCD SPI 노이즈 개선

- 터치 동작 시 화면 지지직 노이즈가 남아 있어 LCD SPI 속도를 낮춰 해결
- `tft_lcd_sv.sv`의 `spi` 모듈에 1비트 분주 enable을 추가
- 기존 LCD SPI FSM을 매 `clk`마다 진행하지 않고 2클럭에 한 번만 진행
- 100MHz 입력 기준 LCD `tft_sck`를 약 50MHz에서 약 25MHz 수준으로 낮춤

```verilog
reg spi_clk_en;

always @(posedge clk, posedge reset_p) begin
    if (reset_p) begin
        spi_clk_en <= 1'b0;
        ...
    end else begin
        spi_clk_en <= ~spi_clk_en;

        if (spi_clk_en) begin
            // 기존 SPI 전송 FSM 진행
        end
    end
end
```

#### 현재 TFT/IP_TEST 기준 유지할 설정

- LCD SPI: 약 25MHz
- XPT2046 DCLK: 기존 `DIV_CNT == 5'd24` 유지
- XPT2046 샘플링 설정:

```verilog
xpt2046 #(
    .CONV_TIMES(20),
    .FILTER_PARAM(3),
    .CNT_TOP(20'd749999)
) touch_pad(...);
```

- 28x28 BRAM write:
  - `Get_Flag` 기반 좌표 latch
  - 50MHz → 100MHz toggle 동기화
  - 새 샘플당 1클럭 write
  - 3x3 브러시 미사용

### TFT IP화 시 반영할 최종 기준

- `canvas_display.v`
  - 240x320 portrait 렌더링
  - y < 240: 28x28 캔버스, 224x224 중앙 배치
  - y >= 240: OK/CLEAR 버튼 렌더링
  - LCD SPI는 약 25MHz로 구동
- `draw_canvas.v`
  - 터치 x 좌표 좌우 반전 보정 포함
  - y < 240이면 canvas BRAM write
  - y >= 240이면 OK/CLEAR 버튼 판정
  - CLEAR 버튼 또는 AXI CTRL[1] 입력 시 BRAM 전체 clear
- `tft_axi.v`
  - STATUS[2] = btn_ok sticky
  - STATUS[3] = btn_clear sticky
  - status read 또는 별도 clear 정책으로 sticky flag 정리
