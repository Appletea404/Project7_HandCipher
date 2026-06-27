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
    // 2. 28x28 중앙 박스 출력 설정 (LCD 매핑)
    // =========================================================
    // 28 * 8(확대) = 224 크기. 화면(240x320) 중앙에 배치하기 위한 여백(Offset) 계산:
    // 가로 시작점: (240 - 224) / 2 = 8
    // 세로 시작점: (320 - 224) / 2 = 48
    wire [7:0] lcd_px = x[9:1]; // 0 ~ 239 물리 픽셀
    wire [8:0] lcd_py = y;      // 0 ~ 319 물리 픽셀

    // 현재 스캔하는 곳이 224x224 중앙 박스 내부인지 확인
    wire in_box_lcd = (lcd_px >= 8 && lcd_px < 232 && lcd_py >= 48 && lcd_py < 272);
    
    // 픽셀을 28x28 인덱스로 변환 (여백을 빼고 8로 나눔: >> 3)
    wire [4:0] grid_x_lcd = (lcd_px - 8) >> 3; 
    wire [4:0] grid_y_lcd = (lcd_py - 48) >> 3;

    reg [9:0] rd_addr; // BRAM 최대 784이므로 10비트
    always @(*) begin
        if (in_box_lcd) rd_addr = (grid_y_lcd * 28) + grid_x_lcd;
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
    wire [15:0] t_x = (touch_x_raw > 239) ? 239 : touch_x_raw;
    wire [15:0] t_y = (touch_y_raw > 319) ? 319 : touch_y_raw;

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

    // latch된 좌표가 224x224 중앙 박스 내부인지 확인한다.
    wire in_box_touch = (touch_x_latched_50 >= 8 && touch_x_latched_50 < 232 &&
                         touch_y_latched_50 >= 48 && touch_y_latched_50 < 272);

    // 터치 좌표를 28x28 그리드 인덱스로 변환한다.
    wire [4:0] grid_x_touch = (touch_x_latched_50 - 8) >> 3;
    wire [4:0] grid_y_touch = (touch_y_latched_50 - 48) >> 3;

    always @(posedge clk or posedge reset_p) begin
        if(reset_p) begin
            wr_addr <= 0;
            data_to_ram <= 0;
            wr_en_reg <= 0;
        end
        else begin
            // 좌표 샘플링이 완료된 순간에만 1클럭 write한다.
            // 28x28 EMNIST 입력이 너무 굵어지지 않도록 한 샘플당 한 칸만 기록한다.
            if (touch_sample_valid && in_box_touch) begin
                wr_addr <= (grid_y_touch * 28) + grid_x_touch;
                data_to_ram <= 8'hFF; // 흰색
                wr_en_reg <= 1'b1;    // BRAM에 1회 쓰기
            end else begin
                wr_en_reg <= 1'b0;
            end
        end
    end

    // =========================================================
    // 6. TFT LCD 디스플레이 출력
    // =========================================================
    // 박스 내부는 BRAM(그림), 박스 외부는 어두운 회색(8'h20)으로 테두리 표시
    wire [7:0] display_data = in_box_lcd ? data_from_ram : 8'h20; 
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
        .framebufferData({8'b0, display_data}), 
        .framebufferClk(framebufferClk), 
        .framebufferIndex(framebufferIndex), 
        .x(x)
    );
    
endmodule














