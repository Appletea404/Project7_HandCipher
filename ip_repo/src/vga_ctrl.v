`timescale 1ns / 1ps

module vga_ctrl #(
    parameter FONT_MEM_FILE = "font_rom.mem"
)(
    input  wire        clk,             // Basys3 system clock: 100MHz
    input  wire        reset_p,         // active-high reset

    input  wire        enable,          // 1이면 VGA 출력 활성화
    input  wire        clear,           // 1클럭 펄스: 문자 버퍼를 space로 초기화
    input  wire        canvas_mode,     // 0=문자 모드, 1=손글씨 프리뷰 합성

    input  wire [10:0] char_wr_addr,    // 문자 버퍼 쓰기 주소: 0~1199
    input  wire [7:0]  char_wr_data,    // ASCII 문자 코드
    input  wire        char_wr_en,      // 1클럭 펄스: 문자 1개 쓰기

    input  wire [9:0]  canvas_wr_addr,  // 캔버스 프리뷰 버퍼 쓰기 주소: 0~783
    input  wire        canvas_wr_data,  // 1=흰색 픽셀, 0=검정 픽셀
    input  wire        canvas_wr_en,    // 1클럭 펄스: 캔버스 픽셀 1개 쓰기

    input  wire [11:0] fg_color,        // RGB444 전경색
    input  wire [11:0] bg_color,        // RGB444 배경색

    output reg  [3:0]  vgaRed,
    output reg  [3:0]  vgaGreen,
    output reg  [3:0]  vgaBlue,
    output reg         Hsync,
    output reg         Vsync,
    output wire        clear_busy       // clear 진행 중이면 1
    );

    localparam H_VISIBLE = 10'd640;
    localparam H_FRONT   = 10'd16;
    localparam H_SYNC    = 10'd96;
    localparam H_BACK    = 10'd48;
    localparam H_TOTAL   = 10'd800;

    localparam V_VISIBLE = 10'd480;
    localparam V_FRONT   = 10'd10;
    localparam V_SYNC    = 10'd2;
    localparam V_BACK    = 10'd33;
    localparam V_TOTAL   = 10'd525;

    localparam PREVIEW_X0 = 10'd16;
    localparam PREVIEW_Y0 = 10'd48;
    localparam PREVIEW_W  = 10'd224;
    localparam PREVIEW_H  = 10'd224;

    (* ram_style = "distributed" *) reg [7:0] char_buf [0:1199];
    (* ram_style = "distributed" *) reg canvas_buf [0:783];

    reg [10:0] clear_idx;
    reg        clear_active;

    assign clear_busy = clear_active;

    reg [1:0] pix_phase;
    reg [9:0] h_cnt;
    reg [9:0] v_cnt;

    wire visible_now = (h_cnt < H_VISIBLE) && (v_cnt < V_VISIBLE);

    // 16x16 폰트 기준: 640/16=40 columns, 480/16=30 rows.
    wire [5:0] char_col = h_cnt[9:4];  // 0~39
    wire [4:0] char_row = v_cnt[8:4];  // 0~29
    wire [3:0] char_x   = h_cnt[3:0];  // 0~15
    wire [3:0] char_y   = v_cnt[3:0];  // 0~15

    // char_row * 40 + char_col = row*32 + row*8 + col
    wire [10:0] char_rd_addr =
        ({6'd0, char_row} << 5) + ({6'd0, char_row} << 3) + {5'd0, char_col};

    wire in_preview_now =
        canvas_mode &&
        (h_cnt >= PREVIEW_X0) && (h_cnt < (PREVIEW_X0 + PREVIEW_W)) &&
        (v_cnt >= PREVIEW_Y0) && (v_cnt < (PREVIEW_Y0 + PREVIEW_H));

    wire [4:0] preview_x = (h_cnt - PREVIEW_X0) >> 3;
    wire [4:0] preview_y = (v_cnt - PREVIEW_Y0) >> 3;

    wire [9:0] canvas_rd_addr =
        ({5'd0, preview_y} << 5) - ({5'd0, preview_y} << 2) + {5'd0, preview_x};

    reg [7:0] char_code_q;
    reg       canvas_pixel_q;

    reg       visible_q;
    reg       in_preview_q;
    reg [3:0] char_x_q;
    reg [3:0] char_y_q;

    reg       visible_d;
    reg       in_preview_d;
    reg [3:0] char_x_d;
    reg       canvas_pixel_d;

    wire [10:0] font_addr = {char_code_q[6:0], char_y_q};
    wire [15:0] font_data;

    font_rom #(
        .FONT_MEM_FILE(FONT_MEM_FILE)
    ) u_font_rom(
        .clk(clk),
        .addr(font_addr),
        .data(font_data)
    );

    wire text_pixel_on = font_data[4'd15 - char_x_d];

    reg [11:0] render_color;

    // RAM 접근은 reset 없는 별도 clocked block에 둔다.
    // 그래야 Vivado가 문자 버퍼를 FF가 아니라 RAM으로 추론한다.
    always @(posedge clk) begin
        if (clear_active) begin
            char_buf[clear_idx] <= 8'h20;
        end
        else if (char_wr_en && (char_wr_addr < 11'd1200)) begin
            char_buf[char_wr_addr] <= char_wr_data;
        end

        if (canvas_wr_en && (canvas_wr_addr < 10'd784)) begin
            canvas_buf[canvas_wr_addr] <= canvas_wr_data;
        end

        if (pix_phase == 2'd0) begin
            char_code_q    <= char_buf[char_rd_addr];
            canvas_pixel_q <= in_preview_now ? canvas_buf[canvas_rd_addr] : 1'b0;
        end
    end

    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            pix_phase      <= 2'd0;
            h_cnt          <= 10'd0;
            v_cnt          <= 10'd0;

            Hsync          <= 1'b1;
            Vsync          <= 1'b1;
            vgaRed         <= 4'h0;
            vgaGreen       <= 4'h0;
            vgaBlue        <= 4'h0;

            clear_idx      <= 11'd0;
            clear_active   <= 1'b0;

            visible_q      <= 1'b0;
            in_preview_q   <= 1'b0;
            char_x_q       <= 4'd0;
            char_y_q       <= 4'd0;
            visible_d      <= 1'b0;
            in_preview_d   <= 1'b0;
            char_x_d       <= 4'd0;
            canvas_pixel_d <= 1'b0;
            render_color   <= 12'h000;
        end
        else begin
            if (clear) begin
                clear_active <= 1'b1;
                clear_idx    <= 11'd0;
            end
            else if (clear_active) begin
                if (clear_idx == 11'd1199)
                    clear_active <= 1'b0;
                else
                    clear_idx <= clear_idx + 11'd1;
            end

            pix_phase <= pix_phase + 2'd1;

            if (pix_phase == 2'd0) begin
                visible_q      <= visible_now;
                in_preview_q   <= in_preview_now;
                char_x_q       <= char_x;
                char_y_q       <= char_y;
            end

            if (pix_phase == 2'd1) begin
                visible_d      <= visible_q;
                in_preview_d   <= in_preview_q;
                char_x_d       <= char_x_q;
                canvas_pixel_d <= canvas_pixel_q;
            end

            if (pix_phase == 2'd3) begin
                Hsync <= ~((h_cnt >= (H_VISIBLE + H_FRONT)) &&
                           (h_cnt <  (H_VISIBLE + H_FRONT + H_SYNC)));
                Vsync <= ~((v_cnt >= (V_VISIBLE + V_FRONT)) &&
                           (v_cnt <  (V_VISIBLE + V_FRONT + V_SYNC)));

                if (!enable || !visible_d) begin
                    render_color = 12'h000;
                end
                else if (in_preview_d) begin
                    render_color = canvas_pixel_d ? 12'hFFF : 12'h000;
                end
                else if (text_pixel_on) begin
                    render_color = fg_color;
                end
                else begin
                    render_color = bg_color;
                end

                vgaRed   <= render_color[11:8];
                vgaGreen <= render_color[7:4];
                vgaBlue  <= render_color[3:0];

                if (h_cnt == (H_TOTAL - 10'd1)) begin
                    h_cnt <= 10'd0;
                    if (v_cnt == (V_TOTAL - 10'd1))
                        v_cnt <= 10'd0;
                    else
                        v_cnt <= v_cnt + 10'd1;
                end
                else begin
                    h_cnt <= h_cnt + 10'd1;
                end
            end
        end
    end

endmodule
