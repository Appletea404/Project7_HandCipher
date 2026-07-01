#ifndef DISPLAY_H_
#define DISPLAY_H_

#include "xil_types.h"

// 색상 정의 (RGB444)
#define WHITE       0xFFFU
#define BLACK       0x000U
#define CYAN        0x0FFU
#define GREEN       0x0F0U
#define RED         0xF00U
#define YELLOW      0xFF0U
#define GRAY        0x888U
#define DARK_BLUE   0x008U

void vga_putchar(u32 base, int row, int col, char c, u32 fg, u32 bg);
void vga_puts(u32 base, int row, int col, const char *str, u32 fg, u32 bg);
void vga_clear(u32 base);
void display_drawing(u32 base, char inferred, char *plain, char *cipher, int len, int shift, int mode);
void display_confirming(u32 base, char inferred, int shift, int mode, char *plain, char *cipher, int len);

#endif /* DISPLAY_H_ */