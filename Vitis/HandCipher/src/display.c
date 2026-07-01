#include "display.h"
#include "xil_io.h"

#define VGA_CHAR_ADDR       0x04U
#define VGA_CHAR_DATA       0x08U
#define VGA_CHAR_WR         0x0CU

// 40x30 텍스트 화면의 특정 행(row), 열(col)에 문자 하나 쓰기
void vga_putchar(u32 base, int row, int col, char c, u32 fg, u32 bg) {
    u32 pos = (u32)(row * 40 + col);
    
    // 1. 전경색 및 배경색 설정
    Xil_Out32(base + 0x10U, fg); // FG_COLOR
    Xil_Out32(base + 0x14U, bg); // BG_COLOR
    
    // 2. 주소 및 데이터 입력
    Xil_Out32(base + VGA_CHAR_ADDR, pos);
    Xil_Out32(base + VGA_CHAR_DATA, (u32)c);
    
    // 3. 쓰기 펄스 인가
    Xil_Out32(base + VGA_CHAR_WR, 1U);
}

// 문자열 출력 함수
void vga_puts(u32 base, int row, int col, const char *str, u32 fg, u32 bg) {
    while (*str != '\0') {
        vga_putchar(base, row, col, *str, fg, bg);
        col++;
        if (col >= 40) { // 화면 줄바꿈 처리
            col = 0;
            row++;
        }
        str++;
    }
}

// 화면 전체를 공백(' ')으로 채우고 지우기
void vga_clear(u32 base) {
    // CTRL 레지스터 [0]=enable(1), [1]=clear(1) -> 0x03U 로 기동하여 VGA 출력을 켜고 지웁니다.
    Xil_Out32(base + 0x00U, 0x03U); 
    
    // 하드웨어 내에서 클리어가 완전히 완료(clear_busy == 0)될 때까지 폴링하여 대기
    // (clear_busy는 CTRL 레지스터 읽기 시 bit 1에 위치함)
    while (Xil_In32(base + 0x00U) & 0x02U) {
        __asm__("nop");
    }
}

// DRAWING 상태 화면 (텍스트 모드)
void display_drawing(u32 base, char inferred, char *plain, char *cipher, int len, int shift, int mode) {
    vga_clear(base);
    
    vga_puts(base, 0, 6, "=== CAESAR CIPHER SYSTEM ===", WHITE, DARK_BLUE);
    
    // MODE: DECRYPT / ENCRYPT   SHIFT: +X
    vga_puts(base, 2, 0, "MODE: ", CYAN, BLACK);
    vga_puts(base, 2, 6, mode ? "DECRYPT  " : "ENCRYPT  ", CYAN, BLACK);
    vga_puts(base, 2, 17, "SHIFT: +", CYAN, BLACK);
    
    char shift_str[4];
    shift_str[0] = '0' + (shift / 10);
    shift_str[1] = '0' + (shift % 10);
    shift_str[2] = '\0';
    
    if (shift_str[0] == '0') {
        vga_puts(base, 2, 25, &shift_str[1], CYAN, BLACK);
        vga_puts(base, 2, 26, " ", CYAN, BLACK);
    } else {
        vga_puts(base, 2, 25, shift_str, CYAN, BLACK);
    }
    
    // 실시간 NPU 결과 및 지침을 캔버스 오른쪽에 출력 (x=16열 시작)
    vga_puts(base, 6, 16, "NPU Result : ", YELLOW, BLACK);
    vga_putchar(base, 6, 29, inferred, YELLOW, BLACK);
    vga_puts(base, 10, 16, "TFT OK  = COMMIT", GREEN, BLACK);
    vga_puts(base, 12, 16, "TFT CLR = CLEAR", RED, BLACK);

    plain[len] = '\0'; 
    cipher[len] = '\0';
    
    vga_puts(base, 22, 0, "Plaintext  : ", GREEN, BLACK);
    vga_puts(base, 22, 13, plain, GREEN, BLACK);
    for (int i = len; i < 25; i++) {
        vga_putchar(base, 22, 13 + i, ' ', GREEN, BLACK);
    }
    
    vga_puts(base, 24, 0, "Ciphertext : ", CYAN, BLACK);
    vga_puts(base, 24, 13, cipher, CYAN, BLACK);
    for (int i = len; i < 25; i++) {
        vga_putchar(base, 24, 13 + i, ' ', CYAN, BLACK);
    }

    vga_puts(base, 29, 0, "UART: +,- Shift / M Mode / R Reset", GRAY, BLACK);
}

// CONFIRMING 상태 화면 (레거시 지원용 스텁)
void display_confirming(u32 base, char inferred, int shift, int mode, char *plain, char *cipher, int len) {
    display_drawing(base, inferred, plain, cipher, len, shift, mode);
}