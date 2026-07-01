#include "xparameters.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "caesar.h"
#include "display.h"
#include "xgpio.h"

// 하드웨어 베이스 주소 매핑
#define NPU_BASE            XPAR_HANDCIPHER_EMNIST_NPU_0_BASEADDR
#define VGA_BASE            XPAR_HANDCIPHER_VGA_0_BASEADDR
#define TFT_BASE            XPAR_HANDCIPHER_TFT_LCD_0_BASEADDR

// 레지스터 오프셋 정의
#define NPU_CTRL            (NPU_BASE + 0x00)
#define NPU_STATUS          (NPU_BASE + 0x04)
#define NPU_RESULT          (NPU_BASE + 0x08)

#define TFT_CTRL            (TFT_BASE + 0x00)
#define TFT_STATUS          (TFT_BASE + 0x0C)
#define TFT_CANVAS_ADDR     (TFT_BASE + 0x10)
#define TFT_CANVAS_DATA     (TFT_BASE + 0x14)

#define VGA_CANVAS_ADDR     (VGA_BASE + 0x18)
#define VGA_CANVAS_DATA     (VGA_BASE + 0x1C)
#define VGA_CANVAS_EN       (VGA_BASE + 0x20)
#define VGA_CANVAS_MODE     (VGA_BASE + 0x24)



char plain_buf[64]  = {0};
char cipher_buf[64] = {0};
int  buf_len = 0;

// ★ 자일링스 기본 헤더 꼬임 방지용 수동 1ms 대기 함수
void custom_delay_ms(u32 ms) {
    volatile u32 count;
    for (u32 i = 0; i < ms; i++) {
        // MicroBlaze가 코드를 마음대로 생략하지 못하도록 nop(No Operation) 어셈블리 주입
        for (count = 0; count < 8000U; count++) {
            __asm__("nop");
        }
    }
}

// TFT LCD 캔버스를 초기화하고 터치를 활성화 상태로 유지하는 함수
void clear_tft_canvas() {
    // CTRL 레지스터 [0]=enable(1), [1]=clear(1) -> 0x03U 로 기동하여 터치를 켜둔 상태로 지웁니다.
    Xil_Out32(TFT_CTRL, 0x03U); 
    
    // 지우기 연산이 끝날 때까지 (clear_busy == 0) 대기 (CTRL 레지스터 bit 1)
    while (Xil_In32(TFT_CTRL) & 0x02U) {
        __asm__("nop");
    }
}

// TFT LCD의 784픽셀을 VGA 내부 프리뷰 버퍼로 복사하는 함수
void transfer_canvas_to_vga() {
    for (int i = 0; i < 784; i++) {
        Xil_Out32(TFT_CANVAS_ADDR, (u32)i);
        u32 px = Xil_In32(TFT_CANVAS_DATA) & 0x1U;
        
        Xil_Out32(VGA_CANVAS_ADDR, (u32)i);
        Xil_Out32(VGA_CANVAS_DATA, px);
        Xil_Out32(VGA_CANVAS_EN, 1U); 
    }
}

// VGA 내부 프리뷰 캔버스를 0으로 채워 지우는 함수
void clear_vga_canvas() {
    for (int i = 0; i < 784; i++) {
        Xil_Out32(VGA_CANVAS_ADDR, (u32)i);
        Xil_Out32(VGA_CANVAS_DATA, 0U);
        Xil_Out32(VGA_CANVAS_EN, 1U);
    }
}

#define USE_SOFTWARE_NPU 1

#if USE_SOFTWARE_NPU
#include "npu_weights.h"

// 소프트웨어 EMNIST 추론 (MLP 784 -> 64 -> 26)
char perform_software_inference(void) {
    static s32 x[784];
    static u8 hidden[64];
    static s32 scores[26];
    
    // 1. TFT 캔버스에서 픽셀 읽어 0 또는 255로 스케일링
    for (int i = 0; i < 784; i++) {
        Xil_Out32(TFT_CANVAS_ADDR, (u32)i);
        u32 px = Xil_In32(TFT_CANVAS_DATA) & 0x1U;
        x[i] = px ? 255 : 0;
    }
    
    // 2. 레이어 1 (은닉층) 연산
    for (int h = 0; h < 64; h++) {
        s32 sum = biases_l1[h];
        for (int i = 0; i < 784; i++) {
            sum += x[i] * weights_l1[h * 784 + i];
        }
        s32 val = sum >> SHIFT_L1;
        if (val < 0) val = 0;
        if (val > 255) val = 255;
        hidden[h] = (u8)val;
    }
    
    // 3. 레이어 2 (출력층) 연산
    for (int o = 0; o < 26; o++) {
        s32 sum = biases_l2[o];
        for (int h = 0; h < 64; h++) {
            sum += (s32)hidden[h] * weights_l2[o * 64 + h];
        }
        scores[o] = sum;
    }
    
    // 4. Argmax
    int best_idx = 0;
    s32 max_score = scores[0];
    for (int o = 1; o < 26; o++) {
        if (scores[o] > max_score) {
            max_score = scores[o];
            best_idx = o;
        }
    }
    
    return 'A' + best_idx;
}
#endif

int main() {
    char inferred_char = '?';
    
    // 암호해독기 개발이므로 기본 모드를 DECRYPT(1)로 설정
    int shift = 3;
    int mode  = 1; // 0: ENCRYPT, 1: DECRYPT

    // 이전 터치 및 버튼 상태를 저장할 변수 (Edge Detection용)
    int prev_ok = 0;
    int prev_clear = 0;
    u32 prev_btn = 0;
    int prev_sw0 = 0;

    // AXI GPIO 초기화
    XGpio gpio;
    if (XGpio_Initialize(&gpio, XPAR_AXI_GPIO_0_BASEADDR) != XST_SUCCESS) {
        xil_printf("GPIO Initialization Failed!\r\n");
    }
    XGpio_SetDataDirection(&gpio, 1, 0xFFFFFFFF); // Channel 1: input (buttons)
    XGpio_SetDataDirection(&gpio, 2, 0xFFFFFFFF); // Channel 2: input (switches)

    // IP 초기 가동 활성화 및 TFT 캔버스 초기화
    Xil_Out32(VGA_BASE + 0x00U, 0x01U); // VGA Enable
    Xil_Out32(TFT_CTRL, 0x01U);         // TFT Enable
    clear_tft_canvas();                 // TFT 캔버스 초기화하며 활성화 유지
    clear_vga_canvas();                 // VGA 캔버스 버퍼 초기화
    Xil_Out32(VGA_CANVAS_MODE, 1U);     // VGA 캔버스 표시 모드 상시 활성화
    
    // 첫 화면 렌더링
    display_drawing(VGA_BASE, inferred_char, plain_buf, cipher_buf, buf_len, shift, mode);

    xil_printf("HandCipher Decoder System Boot Up Successfully (TFT Touch Mode).\r\n");

    while (1) {
        // TFT의 가상 터치 버튼 상태 및 실시간 터치 입력 여부 읽기
        u32 tft_st    = Xil_In32(TFT_STATUS);
        int touch_valid = (int)(tft_st & 0x01U);       // 실시간 그리기 터치 중 여부 (bit 0)
        int touch_ok    = (int)((tft_st >> 2) & 0x1U); // 녹색 OK 버튼 터치 여부
        int touch_clear = (int)((tft_st >> 3) & 0x1U); // 빨간 CLR 버튼 터치 여부

        // GPIO 버튼 및 스위치 입력 읽기
        u32 btn_val = XGpio_DiscreteRead(&gpio, 1);
        u32 sw_val  = XGpio_DiscreteRead(&gpio, 2);

        // 버튼 Edge 감지 (0 -> 1이 되는 순간만 감지)
        u32 btn_pressed = btn_val & (~prev_btn);
        prev_btn = btn_val;

        int btnU_pressed = (btn_pressed & 0x01) ? 1 : 0; // Bit 0: btnU (T18)
        int btnL_pressed = (btn_pressed & 0x02) ? 1 : 0; // Bit 1: btnL (W19)
        int btnR_pressed = (btn_pressed & 0x04) ? 1 : 0; // Bit 2: btnR (T17)
        int btnD_pressed = (btn_pressed & 0x08) ? 1 : 0; // Bit 3: btnD (U17)

        // 스위치 Edge 감지 (SW0 리셋용)
        int sw0_val = (sw_val & 0x0001) ? 1 : 0;         // Bit 0: sw0 (V17)
        int sw0_triggered = sw0_val && !prev_sw0;
        prev_sw0 = sw0_val;

        int new_mode = (sw_val & 0x8000) ? 1 : 0;        // Bit 15: sw15 (R2)

        // 연속 터치(Double-Triggering) 방지를 위한 터치 Edge 감지
        int ok_pressed    = touch_ok && !prev_ok;
        int clear_pressed = touch_clear && !prev_clear;

        // 다음 루프를 위해 이전 터치 상태 업데이트
        prev_ok    = touch_ok;
        prev_clear = touch_clear;

        int config_changed = 0;

        // 스위치 및 물리 버튼 상태 변경 처리
        if (new_mode != mode) {
            mode = new_mode;
            xil_printf("Mode changed via Switch: %s\r\n", mode ? "DECRYPT" : "ENCRYPT");
            config_changed = 1;
        }

        if (sw0_triggered) {
            buf_len = 0;
            plain_buf[0] = '\0';
            cipher_buf[0] = '\0';
            shift = 3;                      // 시프트 값 초기값(3)으로 리셋
            clear_tft_canvas();
            clear_vga_canvas();
            inferred_char = '?';
            xil_printf("System Reset via Switch SW0 (Shift reset to 3).\r\n");
            config_changed = 1;
        }

        if (btnU_pressed) {
            shift = (shift + 1) % 26;
            xil_printf("Shift increased via Button U (T18): +%d\r\n", shift);
            config_changed = 1;
        }

        if (btnD_pressed) {
            shift = (shift + 25) % 26;
            xil_printf("Shift decreased via Button D (U17): +%d\r\n", shift);
            config_changed = 1;
        }

        if (btnL_pressed) {
            buf_len = 0;
            plain_buf[0] = '\0';
            cipher_buf[0] = '\0';
            clear_tft_canvas();
            clear_vga_canvas();
            inferred_char = '?';
            xil_printf("Buffers cleared via Button L (W19).\r\n");
            config_changed = 1;
        }

        if (btnR_pressed){
            if(buf_len >  0)
            {
                buf_len--;
                config_changed = 1;                
            }
        }

        // === 실시간 드로잉 및 추론, 확정(Commit)/지우기(Clear) 처리 ===
        
        // 사용자가 그림을 그리는 중이면 실시간으로 VGA 프리뷰 버퍼에 전송하고 실시간 추론 수행
        if (touch_valid) {
            transfer_canvas_to_vga();
#if USE_SOFTWARE_NPU
            inferred_char = perform_software_inference();
#else
            // 1. NPU 추론 엔진 시작 구동
            Xil_Out32(NPU_CTRL, 1U);
            // 2. NPU 연산 완료까지 하드웨어 폴링 대기
            while (!(Xil_In32(NPU_STATUS) & 0x1U));
            // 3. 추론 결과 획득 (0~25의 값을 알파벳 문자로 변환)
            inferred_char = 'A' + (char)(Xil_In32(NPU_RESULT) & 0x1FU);
#endif
            // VGA 화면에 실시간 추론 문자 업데이트
            vga_putchar(VGA_BASE, 6, 29, inferred_char, YELLOW, BLACK);
        }

        // TFT OK 터치 누름 -> 현재 검증 결과를 최종 확정(Commit)
        int ok_event = ok_pressed;
        if (ok_event) {
            if (inferred_char != '?') {
                char cipher_c = mode ? caesar_decode(inferred_char, shift)
                                     : caesar_encode(inferred_char, shift);
                
                if (buf_len < 64) {
                    plain_buf[buf_len]  = inferred_char;
                    cipher_buf[buf_len] = cipher_c;
                    buf_len++;
                }
            }
            
            clear_tft_canvas();             // TFT 하드웨어 캔버스 초기화
            clear_vga_canvas();             // VGA 캔버스도 초기화
            inferred_char = '?';            // 검증 문자 초기화
            config_changed = 1;
        }
        
        // TFT CLR 터치 -> 화면 지우기 및 검증 초기화
        if (clear_pressed) {
            clear_tft_canvas();             // TFT 하드웨어 캔버스 초기화
            clear_vga_canvas();             // VGA 캔버스도 초기화
            inferred_char = '?';            // 검증 문자 초기화
            config_changed = 1;
        }

        if (config_changed) {
            display_drawing(VGA_BASE, inferred_char, plain_buf, cipher_buf, buf_len, shift, mode);
        }
        
        // SPI 터치 컨트롤러(XPT2046)의 타이밍 확보 및 CPU 과부하 방지를 위한 1ms 대기
        custom_delay_ms(1); 
    }
    return 0;
}