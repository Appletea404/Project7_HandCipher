`timescale 1ns / 1ps

module tb_vga;

    reg         clk = 1'b0;
    reg         reset_p = 1'b1;

    reg         enable = 1'b0;
    reg         clear = 1'b0;
    reg         canvas_mode = 1'b0;

    reg [10:0]  char_wr_addr = 11'd0;
    reg [7:0]   char_wr_data = 8'h00;
    reg         char_wr_en = 1'b0;

    reg [9:0]   canvas_wr_addr = 10'd0;
    reg         canvas_wr_data = 1'b0;
    reg         canvas_wr_en = 1'b0;

    reg [11:0]  fg_color = 12'h0F0;
    reg [11:0]  bg_color = 12'h001;

    wire [3:0]  vgaRed;
    wire [3:0]  vgaGreen;
    wire [3:0]  vgaBlue;
    wire        Hsync;
    wire        Vsync;
    wire        clear_busy;

    localparam FONT_MEM_FILE = "/home/appletea/workspace_onedevice_2/Project_7_HandCipher/Vivado/IP_TEST/IP_TEST.srcs/sources_1/new/font_rom.mem";

    vga_ctrl #(
        .FONT_MEM_FILE(FONT_MEM_FILE)
    ) uut(
        .clk(clk),
        .reset_p(reset_p),
        .enable(enable),
        .clear(clear),
        .canvas_mode(canvas_mode),
        .char_wr_addr(char_wr_addr),
        .char_wr_data(char_wr_data),
        .char_wr_en(char_wr_en),
        .canvas_wr_addr(canvas_wr_addr),
        .canvas_wr_data(canvas_wr_data),
        .canvas_wr_en(canvas_wr_en),
        .fg_color(fg_color),
        .bg_color(bg_color),
        .vgaRed(vgaRed),
        .vgaGreen(vgaGreen),
        .vgaBlue(vgaBlue),
        .Hsync(Hsync),
        .Vsync(Vsync),
        .clear_busy(clear_busy)
    );

    always #5 clk = ~clk; // 100MHz

    task write_char;
        input [10:0] addr;
        input [7:0] data;
        begin
            @(posedge clk);
            char_wr_addr <= addr;
            char_wr_data <= data;
            char_wr_en   <= 1'b1;
            @(posedge clk);
            char_wr_en   <= 1'b0;
        end
    endtask

    task write_canvas;
        input [9:0] addr;
        input data;
        begin
            @(posedge clk);
            canvas_wr_addr <= addr;
            canvas_wr_data <= data;
            canvas_wr_en   <= 1'b1;
            @(posedge clk);
            canvas_wr_en   <= 1'b0;
        end
    endtask

    task pulse_clear;
        begin
            @(posedge clk);
            clear <= 1'b1;
            @(posedge clk);
            clear <= 1'b0;
        end
    endtask

    task wait_pixel;
        input [9:0] x;
        input [9:0] y;
        begin
            while (!(uut.pix_phase == 2'd3 && uut.h_cnt == x && uut.v_cnt == y))
                @(posedge clk);
            @(posedge clk);
        end
    endtask

    integer hsync_low_pixels;

    initial begin
        $dumpfile("tb_vga.vcd");
        $dumpvars(0, tb_vga);

        repeat (8) @(posedge clk);
        reset_p <= 1'b0;
        enable  <= 1'b1;

        // 문자 버퍼 쓰기 확인: 화면 좌상단에 'A' 저장
        write_char(11'd0, 8'h41);
        repeat (2) @(posedge clk);
        if (uut.char_buf[0] !== 8'h41) begin
            $display("FAIL: char_buf[0] write failed. value=%h", uut.char_buf[0]);
            $fatal;
        end

        // 캔버스 프리뷰 버퍼 쓰기 확인: 첫 픽셀을 흰색으로 저장
        write_canvas(10'd0, 1'b1);
        repeat (2) @(posedge clk);
        if (uut.canvas_buf[0] !== 1'b1) begin
            $display("FAIL: canvas_buf[0] write failed. value=%b", uut.canvas_buf[0]);
            $fatal;
        end

        // clear는 1200클럭 동안 문자 버퍼를 순차적으로 space로 채운다.
        pulse_clear();
        wait (clear_busy == 1'b1);
        wait (clear_busy == 1'b0);
        repeat (2) @(posedge clk);
        if (uut.char_buf[0] !== 8'h20 || uut.char_buf[1199] !== 8'h20) begin
            $display("FAIL: clear failed. char0=%h char1199=%h", uut.char_buf[0], uut.char_buf[1199]);
            $fatal;
        end

        // clear가 끝난 뒤 다시 문자와 캔버스를 넣어 파형에서 렌더링을 확인한다.
        write_char(11'd0, 8'h48);       // 'H'
        write_char(11'd1, 8'h49);       // 'I'
        write_char(11'd40, 8'h41);      // 다음 줄 'A'
        write_canvas(10'd0, 1'b1);
        write_canvas(10'd29, 1'b1);
        canvas_mode <= 1'b1;

        // 한 줄은 800픽셀이고, 픽셀당 4개의 100MHz 클럭을 쓴다.
        wait_pixel(10'd799, 10'd0);
        @(posedge clk);
        if (uut.h_cnt !== 10'd0 || uut.v_cnt !== 10'd1) begin
            $display("FAIL: line rollover failed. h=%0d v=%0d", uut.h_cnt, uut.v_cnt);
            $fatal;
        end

        // Hsync active-low 구간은 96픽셀이어야 한다.
        hsync_low_pixels = 0;
        wait_pixel(10'd0, 10'd2);
        while (uut.v_cnt == 10'd2) begin
            if (uut.pix_phase == 2'd3 && Hsync == 1'b0)
                hsync_low_pixels = hsync_low_pixels + 1;
            @(posedge clk);
        end
        if (hsync_low_pixels != 96) begin
            $display("FAIL: Hsync low width mismatch. got=%0d expected=96", hsync_low_pixels);
            $fatal;
        end

        // 프리뷰 영역 시작점 근처까지 진행해서 VCD에서 canvas_mode 렌더링을 볼 수 있게 한다.
        wait_pixel(10'd20, 10'd50);
        repeat (200) @(posedge clk);

        $display("PASS: tb_vga completed");
        $finish;
    end

endmodule
