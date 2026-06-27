`timescale 1ns / 1ps

module tft_lcd_top_HY(
    input clk, reset_p,
    input tft_sdo, 
    output tft_sck, 
    output tft_sdi, 
    output tft_dc, 
    output tft_reset, 
    output tft_cs,
    
    input PenIrq_n,
    output DCLK,
    output DIN,
    output CS_N,
    input  DOUT
);
    
    // =========================================================
    // 1. 디스플레이 Y좌표 동기화 복원 (tft_sv 수정 없이 x로 유추)
    // =========================================================
    wire [9:0] x;
    reg [8:0] y; 
    reg [9:0] prev_x;     

    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            y <= 0;
            prev_x <= 0;
        end else begin
            prev_x <= x; 
            // x가 479 끝까지 갔다가 0으로 떨어질 때 y를 1 증가
            if (prev_x == 479 && x == 0) begin
                if (y >= 319) y <= 0;
                else y <= y + 1;
            end
        end
    end

    // =========================================================
    // 2. TFT 화면 레이아웃 (PLAN.md 기준)
    // =========================================================
    // 화면: 240x320 portrait
    // y:   0~239  캔버스 영역
    // y: 240~319  터치 버튼 영역 (왼쪽 OK, 오른쪽 CLEAR)
    // 28x28 입력은 셀당 8px로 확대하면 224x224가 되므로,
    // 240x240 캔버스 영역 안에서 x/y 각각 8px 여백을 둔다.
    // tft_sv의 scan x 방향이 실제 LCD에서 좌우 반전되어 보이므로 표시용 x를 보정한다.
    wire [7:0] lcd_px_raw = x[9:1]; // 0 ~ 239 물리 픽셀
    wire [7:0] lcd_px = 8'd239 - lcd_px_raw;
    wire [8:0] lcd_py = y;      // 0 ~ 319 물리 픽셀

    wire in_canvas_area_lcd = (lcd_py < 240);
    wire in_button_area_lcd = (lcd_py >= 240);
    wire in_ok_button_lcd   = in_button_area_lcd && (lcd_px < 120);
    wire in_clr_button_lcd  = in_button_area_lcd && (lcd_px >= 120);

    // 실제 28x28 글씨 입력 영역은 224x224이며, 240x240 영역 안에 중앙 배치한다.
    wire in_canvas_grid_lcd = (lcd_px >= 8 && lcd_px < 232 &&
                               lcd_py >= 8 && lcd_py < 232);

    wire [4:0] grid_x_lcd = (lcd_px - 8) >> 3;
    wire [4:0] grid_y_lcd = (lcd_py - 8) >> 3;

    // 버튼 안에 간단한 5x7 블록 글자를 4배 확대해서 그린다.
    // OK: 2글자 폭 44px, CLR: 3글자 폭 68px가 되도록 버튼 중앙에 배치한다.
    wire [7:0] btn_x = in_ok_button_lcd ? lcd_px : (lcd_px - 120);
    wire [6:0] btn_y = lcd_py - 240;

    wire [7:0] ok_text_x  = btn_x - 38;
    wire [6:0] ok_text_y  = btn_y - 26;
    wire [7:0] clr_text_x = btn_x - 26;
    wire [6:0] clr_text_y = btn_y - 26;

    wire ok_text_area  = in_ok_button_lcd  && btn_x >= 38 && btn_x < 82  && btn_y >= 26 && btn_y < 54;
    wire clr_text_area = in_clr_button_lcd && btn_x >= 26 && btn_x < 94  && btn_y >= 26 && btn_y < 54;

    wire [2:0] ok_col  = ok_text_x[4:2];
    wire [2:0] ok_row  = ok_text_y[4:2];
    wire [1:0] ok_char = ok_text_x / 8'd24; // 0=O, 1=K
    wire [2:0] ok_gx   = ok_col - (ok_char * 3'd6);

    wire [2:0] clr_col  = clr_text_x[4:2];
    wire [2:0] clr_row  = clr_text_y[4:2];
    wire [1:0] clr_char = clr_text_x / 8'd24; // 0=C, 1=L, 2=R
    wire [2:0] clr_gx   = clr_col - (clr_char * 3'd6);

    wire glyph_o = ((ok_gx == 0 || ok_gx == 4) && ok_row >= 1 && ok_row <= 5) ||
                   ((ok_row == 0 || ok_row == 6) && ok_gx >= 1 && ok_gx <= 3);
    wire glyph_k = (ok_gx == 0) ||
                   (ok_gx == 4 && (ok_row == 0 || ok_row == 1 || ok_row == 5 || ok_row == 6)) ||
                   (ok_gx == 3 && (ok_row == 2 || ok_row == 4)) ||
                   (ok_gx == 2 && ok_row == 3);

    wire glyph_c = ((clr_gx == 0) && clr_row >= 1 && clr_row <= 5) ||
                   ((clr_row == 0 || clr_row == 6) && clr_gx >= 1 && clr_gx <= 4);
    wire glyph_l = (clr_gx == 0) ||
                   (clr_row == 6 && clr_gx >= 0 && clr_gx <= 4);
    wire glyph_r = (clr_gx == 0) ||
                   ((clr_row == 0 || clr_row == 3) && clr_gx >= 0 && clr_gx <= 3) ||
                   (clr_gx == 4 && clr_row >= 1 && clr_row <= 2) ||
                   (clr_gx == 2 && clr_row == 4) ||
                   (clr_gx == 3 && clr_row == 5) ||
                   (clr_gx == 4 && clr_row == 6);

    wire ok_text_lcd = ok_text_area &&
                       ((ok_char == 0 && ok_gx < 5 && glyph_o) ||
                        (ok_char == 1 && ok_gx < 5 && glyph_k));

    wire clr_text_lcd = clr_text_area &&
                        ((clr_char == 0 && clr_gx < 5 && glyph_c) ||
                         (clr_char == 1 && clr_gx < 5 && glyph_l) ||
                         (clr_char == 2 && clr_gx < 5 && glyph_r));

    wire button_text_lcd = ok_text_lcd || clr_text_lcd;

    reg [9:0] rd_addr; // BRAM 최대 784이므로 10비트
    always @(*) begin
        if (in_canvas_grid_lcd) rd_addr = (grid_y_lcd * 28) + grid_x_lcd;
        else rd_addr = 0;
    end

    // =========================================================
    // 3. 초소형 BRAM (28 * 28 = 784)
    // =========================================================
    reg [9:0] wr_addr;
    reg [7:0] data_to_ram;
    wire [7:0] data_from_ram;
    reg wr_en_reg; // 터치 입력 제한을 위해 내부 레지스터 사용

    lcd_bram #(.DEPTH(28*28)) lcd_mem(
        .wclk(clk),
        .wr_en(wr_en_reg), // 조건에 맞을 때만 1이 됨
        .wr_addr(wr_addr),
        
        .rclk(clk),
        .rd_en(1'b1),
        .rd_addr(rd_addr),
        
        .bram_en(1'b1),
        .data_to_ram(data_to_ram),
        .data_from_ram(data_from_ram)
    );

    // =========================================================
    // 4. 터치패드 제어 및 캘리브레이션
    // =========================================================
    reg Clk50M = 0;
    always @(posedge clk) Clk50M <= ~Clk50M; // 클럭 토글 방식으로 안정화
    wire Rst_n = ~reset_p;
    
    wire [11:0] X_Value, Y_Value;
    wire Get_Flag;
    
    // 터치 SPI가 LCD refresh에 주는 간섭을 줄이기 위해 샘플링 시작 간격을 약 15ms로 늦춘다.
    // xpt2046 기본 CNT_TOP=499999는 50MHz 기준 약 10ms이다.
    xpt2046 #(
        .CONV_TIMES(20),
        .FILTER_PARAM(3),
        .CNT_TOP(20'd749999)
    ) touch_pad(
        Clk50M, Rst_n, 1'b1,
        X_Value, Y_Value, Get_Flag,
        PenIrq_n, DCLK, DIN, DOUT, CS_N
    );

    // 노이즈 제거
    wire [11:0] x_tmp = (X_Value > 12'd300) ? (X_Value - 12'd300) : 12'd0;
    wire [11:0] y_tmp = (Y_Value > 12'd300) ? (Y_Value - 12'd300) : 12'd0;

    // 터치 좌표를 240x320 해상도로 변환 (오버플로우 방지를 위해 32비트 연산 사용)
    wire [15:0] touch_x_raw = ((x_tmp * 32'd70) >> 10) + 16'd0; // X축 영점 조절
    wire [15:0] touch_y_320 = ((y_tmp * 32'd94) >> 10);
    wire [15:0] touch_y_raw = ((16'd319 > touch_y_320) ? (16'd319 - touch_y_320) : 16'd0) + 16'd0; // Y축 영점 조절

    // 화면 이탈 방지
    wire [15:0] t_x_raw_clamped = (touch_x_raw > 239) ? 239 : touch_x_raw;
    wire [15:0] t_y = (touch_y_raw > 319) ? 319 : touch_y_raw;

    // LCD 표시 x를 좌우 반전 보정했으므로, 터치 x도 같은 화면 좌표계로 맞춘다.
    wire [15:0] t_x = 16'd239 - t_x_raw_clamped;

    // =========================================================
    // 5. 입력 제한 (Bounding Box 내부만 터치 허용)
    // =========================================================
    // XPT2046의 X/Y/Get_Flag는 Clk50M 도메인에서 나온다.
    // Get_Flag가 뜬 순간의 좌표만 latch하고, clk 도메인에서는 새 샘플당 1회만 BRAM에 쓴다.
    reg [15:0] touch_x_latched_50;
    reg [15:0] touch_y_latched_50;
    reg touch_sample_toggle_50;

    always @(posedge Clk50M or posedge reset_p) begin
        if (reset_p) begin
            touch_x_latched_50 <= 16'd0;
            touch_y_latched_50 <= 16'd0;
            touch_sample_toggle_50 <= 1'b0;
        end else if (Get_Flag && ~PenIrq_n) begin
            touch_x_latched_50 <= t_x;
            touch_y_latched_50 <= t_y;
            touch_sample_toggle_50 <= ~touch_sample_toggle_50;
        end
    end

    // 50MHz 도메인의 toggle을 100MHz clk 도메인으로 동기화한다.
    reg [2:0] touch_sample_sync;
    always @(posedge clk or posedge reset_p) begin
        if (reset_p) touch_sample_sync <= 3'b000;
        else touch_sample_sync <= {touch_sample_sync[1:0], touch_sample_toggle_50};
    end

    wire touch_sample_valid = touch_sample_sync[2] ^ touch_sample_sync[1];

    // 터치 좌표 판정: y<240은 캔버스, y>=240은 버튼 영역이다.
    wire in_canvas_grid_touch = (touch_x_latched_50 >= 8 && touch_x_latched_50 < 232 &&
                                 touch_y_latched_50 >= 8 && touch_y_latched_50 < 232);
    wire in_button_area_touch = (touch_y_latched_50 >= 240);
    wire touch_ok_button      = in_button_area_touch && (touch_x_latched_50 < 120);
    wire touch_clear_button   = in_button_area_touch && (touch_x_latched_50 >= 120);

    // 터치 좌표를 28x28 그리드 인덱스로 변환한다.
    wire [4:0] grid_x_touch = (touch_x_latched_50 - 8) >> 3;
    wire [4:0] grid_y_touch = (touch_y_latched_50 - 8) >> 3;

    // IP_TEST에서는 AXI STATUS가 아직 없으므로 OK는 내부 sticky 플래그로만 보관한다.
    // tft_axi.v로 옮길 때 STATUS[2]에 연결하고, read 시 clear하면 된다.
    reg btn_ok_sticky;
    reg btn_clear_sticky;

    // CLEAR 버튼은 CPU 없이도 IP_TEST에서 바로 확인할 수 있도록 BRAM 전체를 0으로 지운다.
    reg clear_active;
    reg [9:0] clear_addr;

    always @(posedge clk or posedge reset_p) begin
        if(reset_p) begin
            wr_addr <= 0;
            data_to_ram <= 0;
            wr_en_reg <= 0;
            btn_ok_sticky <= 1'b0;
            btn_clear_sticky <= 1'b0;
            clear_active <= 1'b0;
            clear_addr <= 10'd0;
        end
        else begin
            wr_en_reg <= 1'b0;

            if (clear_active) begin
                wr_addr <= clear_addr;
                data_to_ram <= 8'h00;
                wr_en_reg <= 1'b1;

                if (clear_addr >= 10'd783) begin
                    clear_addr <= 10'd0;
                    clear_active <= 1'b0;
                end else begin
                    clear_addr <= clear_addr + 1'b1;
                end
            end
            else if (touch_sample_valid && touch_clear_button) begin
                btn_clear_sticky <= 1'b1;
                clear_addr <= 10'd0;
                clear_active <= 1'b1;
            end
            else if (touch_sample_valid && touch_ok_button) begin
                btn_ok_sticky <= 1'b1;
            end
            else if (touch_sample_valid && in_canvas_grid_touch) begin
                // 좌표 샘플링이 완료된 순간에만 1클럭 write한다.
                // 28x28 EMNIST 입력이 너무 굵어지지 않도록 한 샘플당 한 칸만 기록한다.
                wr_addr <= (grid_y_touch * 28) + grid_x_touch;
                data_to_ram <= 8'hFF;
                wr_en_reg <= 1'b1;
            end
        end
    end

    // =========================================================
    // 6. TFT LCD 디스플레이 출력
    // =========================================================
    // tft_sv 내부에서 SPI로 내보낼 때 byte를 invert하므로,
    // 아래 색상은 실제 RGB565의 bitwise inverse 값으로 둔다.
    localparam [15:0] LCD_RAW_BLACK = 16'hFFFF;
    localparam [15:0] LCD_RAW_WHITE = 16'h0000;
    localparam [15:0] LCD_RAW_GRAY  = 16'hC618; // 실제 약 0x39E7
    localparam [15:0] LCD_RAW_GREEN = 16'hF81F; // 실제 0x07E0
    localparam [15:0] LCD_RAW_RED   = 16'h07FF; // 실제 0xF800

    wire [15:0] canvas_pixel = (in_canvas_grid_lcd && data_from_ram != 8'h00) ?
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














