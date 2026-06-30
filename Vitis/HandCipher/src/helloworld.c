#include "xil_io.h"
#include "xil_printf.h"
#include "xparameters.h"

#define NPU_BASE_ADDR   XPAR_HANDCIPHER_EMNIST_NPU_0_BASEADDR
#define TFT_BASE_ADDR   XPAR_HANDCIPHER_TFT_LCD_0_BASEADDR
#define VGA_BASE_ADDR   XPAR_HANDCIPHER_VGA_0_BASEADDR

#define VGA_CTRL            0x00U
#define VGA_CHAR_ADDR       0x04U
#define VGA_CHAR_DATA       0x08U
#define VGA_CHAR_WR         0x0CU
#define VGA_CANVAS_ADDR     0x18U
#define VGA_CANVAS_DATA     0x1CU
#define VGA_CANVAS_WR       0x20U
#define VGA_CANVAS_MODE     0x24U

#define TFT_CTRL            0x00U
#define TFT_STATUS          0x0CU

static int test_npu(void)
{
    u32 rd;

    Xil_Out32(NPU_BASE_ADDR + 0x00U, 0xAAAABBBBU);
    rd = Xil_In32(NPU_BASE_ADDR + 0x00U);

    xil_printf("NPU CTRL      read=0x%08X expected=0xAAAABBBB\r\n", rd);
    return rd == 0xAAAABBBBU;
}

static int test_tft(void)
{
    u32 ctrl;
    u32 status;

    Xil_Out32(TFT_BASE_ADDR + TFT_CTRL, 0x00000001U);
    ctrl = Xil_In32(TFT_BASE_ADDR + TFT_CTRL);
    status = Xil_In32(TFT_BASE_ADDR + TFT_STATUS);

    xil_printf("TFT CTRL      read=0x%08X enable=%lu\r\n", ctrl, ctrl & 1U);
    xil_printf("TFT STATUS    read=0x%08X\r\n", status);

    return (ctrl & 1U) == 1U;
}

static void vga_put_char(u32 pos, char ch)
{
    Xil_Out32(VGA_BASE_ADDR + VGA_CHAR_ADDR, pos);
    Xil_Out32(VGA_BASE_ADDR + VGA_CHAR_DATA, (u32)ch);
    Xil_Out32(VGA_BASE_ADDR + VGA_CHAR_WR, 1U);
}

static void vga_write_text(u32 pos, const char *text)
{
    while (*text != '\0') {
        vga_put_char(pos, *text);
        pos++;
        text++;
    }
}

static void vga_put_canvas_pixel(u32 addr, u32 bit)
{
    Xil_Out32(VGA_BASE_ADDR + VGA_CANVAS_ADDR, addr);
    Xil_Out32(VGA_BASE_ADDR + VGA_CANVAS_DATA, bit & 1U);
    Xil_Out32(VGA_BASE_ADDR + VGA_CANVAS_WR, 1U);
}

static int test_vga(void)
{
    u32 ctrl;
    u32 mode;
    u32 i;

    Xil_Out32(VGA_BASE_ADDR + VGA_CTRL, 0x00000001U);
    ctrl = Xil_In32(VGA_BASE_ADDR + VGA_CTRL);
    xil_printf("VGA CTRL      read=0x%08X enable=%lu\r\n", ctrl, ctrl & 1U);

    if ((ctrl & 1U) != 1U) {
        return 0;
    }

    Xil_Out32(VGA_BASE_ADDR + VGA_CANVAS_MODE, 0x00000000U);
    mode = Xil_In32(VGA_BASE_ADDR + VGA_CANVAS_MODE);
    xil_printf("VGA TEXTMODE  read=0x%08X\r\n", mode);

    vga_write_text(0U,  "VGA AXI OK");
    vga_write_text(40U, "HANDCIPHER TEST");
    vga_write_text(80U, "TEXT BUFFER OK");

    Xil_Out32(VGA_BASE_ADDR + VGA_CANVAS_MODE, 0x00000001U);
    mode = Xil_In32(VGA_BASE_ADDR + VGA_CANVAS_MODE);
    xil_printf("VGA CANVAS    read=0x%08X mode=%lu\r\n", mode, mode & 1U);

    for (i = 0U; i < 28U; i++) {
        vga_put_canvas_pixel((i * 28U) + i, 1U);
        vga_put_canvas_pixel((i * 28U) + (27U - i), 1U);
    }

    return (mode & 1U) == 1U;
}

int main(void)
{
    int npu_ok;
    int tft_ok;
    int vga_ok;

    xil_printf("\r\nHandCipher connectivity test\r\n");
    xil_printf("NPU base=0x%08X\r\n", (unsigned int)NPU_BASE_ADDR);
    xil_printf("VGA base=0x%08X\r\n", (unsigned int)VGA_BASE_ADDR);
    xil_printf("TFT base=0x%08X\r\n", (unsigned int)TFT_BASE_ADDR);

    npu_ok = test_npu();
    tft_ok = test_tft();
    vga_ok = test_vga();

    xil_printf("\r\nRESULT NPU=%s TFT=%s VGA=%s\r\n",
               npu_ok ? "OK" : "FAIL",
               tft_ok ? "OK" : "FAIL",
               vga_ok ? "OK" : "FAIL");

    while (1) {
    }

    return 0;
}
