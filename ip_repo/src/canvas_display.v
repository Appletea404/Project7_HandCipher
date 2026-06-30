`timescale 1ns / 1ps

module canvas_display(
    input  wire       clk,
    input  wire       reset_p,

    input  wire       tft_sdo,
    output wire       tft_sck,
    output wire       tft_sdi,
    output wire       tft_dc,
    output wire       tft_reset,
    output wire       tft_cs,

    output reg  [9:0] canvas_rd_addr,
    input  wire       canvas_rd_data
    );

    wire [9:0] x;
    reg  [8:0] y;
    reg  [9:0] prev_x;

    // tft_sv는 x만 외부로 내보내므로, x가 한 줄 끝에서 0으로 돌아오는 순간 y를 증가시킨다.
    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            y      <= 9'd0;
            prev_x <= 10'd0;
        end
        else begin
            prev_x <= x;
            if (prev_x == 10'd479 && x == 10'd0) begin
                if (y >= 9'd319)
                    y <= 9'd0;
                else
                    y <= y + 1'b1;
            end
        end
    end

    // 기존 보드 테스트에서 LCD x 방향이 거울처럼 보여 표시 좌표를 좌우 반전했다.
    wire [7:0] lcd_px_raw = x[9:1];
    wire [7:0] lcd_px     = 8'd239 - lcd_px_raw;
    wire [8:0] lcd_py     = y;

    wire in_button_area_lcd = (lcd_py >= 9'd240);
    wire in_ok_button_lcd   = in_button_area_lcd && (lcd_px < 8'd120);
    wire in_clr_button_lcd  = in_button_area_lcd && (lcd_px >= 8'd120);

    // 28x28 캔버스를 8배 확대하면 224x224이며, 240x240 영역 안에 8px 여백을 둔다.
    wire in_canvas_grid_lcd = (lcd_px >= 8'd8 && lcd_px < 8'd232 &&
                               lcd_py >= 9'd8 && lcd_py < 9'd232);

    wire [4:0] grid_x_lcd = (lcd_px - 8'd8) >> 3;
    wire [4:0] grid_y_lcd = (lcd_py[7:0] - 8'd8) >> 3;

    always @(*) begin
        if (in_canvas_grid_lcd)
            canvas_rd_addr = (grid_y_lcd * 10'd28) + grid_x_lcd;
        else
            canvas_rd_addr = 10'd0;
    end

    wire [7:0] btn_x = in_ok_button_lcd ? lcd_px : (lcd_px - 8'd120);
    wire [6:0] btn_y = lcd_py - 9'd240;

    wire [7:0] ok_text_x  = btn_x - 8'd38;
    wire [6:0] ok_text_y  = btn_y - 7'd26;
    wire [7:0] clr_text_x = btn_x - 8'd26;
    wire [6:0] clr_text_y = btn_y - 7'd26;

    wire ok_text_area  = in_ok_button_lcd  && btn_x >= 8'd38 && btn_x < 8'd82 &&
                         btn_y >= 7'd26 && btn_y < 7'd54;
    wire clr_text_area = in_clr_button_lcd && btn_x >= 8'd26 && btn_x < 8'd94 &&
                         btn_y >= 7'd26 && btn_y < 7'd54;

    wire [2:0] ok_col  = ok_text_x[4:2];
    wire [2:0] ok_row  = ok_text_y[4:2];
    wire [1:0] ok_char = ok_text_x / 8'd24;
    wire [2:0] ok_gx   = ok_col - (ok_char * 3'd6);

    wire [2:0] clr_col  = clr_text_x[4:2];
    wire [2:0] clr_row  = clr_text_y[4:2];
    wire [1:0] clr_char = clr_text_x / 8'd24;
    wire [2:0] clr_gx   = clr_col - (clr_char * 3'd6);

    // 버튼 라벨은 별도 폰트 ROM 없이 5x7 블록 글자로 그린다.
    wire glyph_o = ((ok_gx == 3'd0 || ok_gx == 3'd4) && ok_row >= 3'd1 && ok_row <= 3'd5) ||
                   ((ok_row == 3'd0 || ok_row == 3'd6) && ok_gx >= 3'd1 && ok_gx <= 3'd3);
    wire glyph_k = (ok_gx == 3'd0) ||
                   (ok_gx == 3'd4 && (ok_row == 3'd0 || ok_row == 3'd1 || ok_row == 3'd5 || ok_row == 3'd6)) ||
                   (ok_gx == 3'd3 && (ok_row == 3'd2 || ok_row == 3'd4)) ||
                   (ok_gx == 3'd2 && ok_row == 3'd3);

    wire glyph_c = (clr_gx == 3'd0 && clr_row >= 3'd1 && clr_row <= 3'd5) ||
                   ((clr_row == 3'd0 || clr_row == 3'd6) && clr_gx >= 3'd1 && clr_gx <= 3'd4);
    wire glyph_l = (clr_gx == 3'd0) ||
                   (clr_row == 3'd6 && clr_gx <= 3'd4);
    wire glyph_r = (clr_gx == 3'd0) ||
                   ((clr_row == 3'd0 || clr_row == 3'd3) && clr_gx <= 3'd3) ||
                   (clr_gx == 3'd4 && clr_row >= 3'd1 && clr_row <= 3'd2) ||
                   (clr_gx == 3'd2 && clr_row == 3'd4) ||
                   (clr_gx == 3'd3 && clr_row == 3'd5) ||
                   (clr_gx == 3'd4 && clr_row == 3'd6);

    wire ok_text_lcd = ok_text_area &&
                       ((ok_char == 2'd0 && ok_gx < 3'd5 && glyph_o) ||
                        (ok_char == 2'd1 && ok_gx < 3'd5 && glyph_k));

    wire clr_text_lcd = clr_text_area &&
                        ((clr_char == 2'd0 && clr_gx < 3'd5 && glyph_c) ||
                         (clr_char == 2'd1 && clr_gx < 3'd5 && glyph_l) ||
                         (clr_char == 2'd2 && clr_gx < 3'd5 && glyph_r));

    wire button_text_lcd = ok_text_lcd || clr_text_lcd;

    // tft_sv 내부 SPI 전송부가 byte를 invert하므로 RGB565의 bitwise inverse 값을 넣는다.
    localparam [15:0] LCD_RAW_BLACK = 16'hFFFF;
    localparam [15:0] LCD_RAW_WHITE = 16'h0000;
    localparam [15:0] LCD_RAW_GRAY  = 16'hC618;
    localparam [15:0] LCD_RAW_GREEN = 16'hF81F;
    localparam [15:0] LCD_RAW_RED   = 16'h07FF;

    wire [15:0] canvas_pixel = (in_canvas_grid_lcd && canvas_rd_data) ?
                               LCD_RAW_WHITE : LCD_RAW_BLACK;

    wire [15:0] display_pixel = in_button_area_lcd ?
                                (button_text_lcd ? LCD_RAW_WHITE :
                                 (in_ok_button_lcd ? LCD_RAW_GREEN : LCD_RAW_RED)) :
                                (in_canvas_grid_lcd ? canvas_pixel : LCD_RAW_GRAY);

    wire framebufferClk;
    wire [17:0] framebufferIndex;

    tft_sv lcd(
        .clk(clk),
        .reset_p(reset_p),
        .tft_sdo(tft_sdo),
        .tft_sck(tft_sck),
        .tft_sdi(tft_sdi),
        .tft_dc(tft_dc),
        .tft_reset(tft_reset),
        .tft_cs(tft_cs),
        .framebufferData(display_pixel),
        .framebufferClk(framebufferClk),
        .framebufferIndex(framebufferIndex),
        .x(x)
    );

endmodule
