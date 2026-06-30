`timescale 1ns / 1ps

module tb_vga_axi;

    localparam FONT_MEM_FILE = "/home/appletea/workspace_onedevice_2/Project_7_HandCipher/Vivado/IP_TEST/IP_TEST.srcs/sources_1/new/font_rom.mem";

    reg clk = 1'b0;
    reg resetn = 1'b0;

    reg  [5:0]  awaddr = 6'd0;
    reg         awvalid = 1'b0;
    wire        awready;
    reg  [31:0] wdata = 32'd0;
    reg  [3:0]  wstrb = 4'hF;
    reg         wvalid = 1'b0;
    wire        wready;
    wire [1:0]  bresp;
    wire        bvalid;
    reg         bready = 1'b1;

    reg  [5:0]  araddr = 6'd0;
    reg         arvalid = 1'b0;
    wire        arready;
    wire [31:0] rdata;
    wire [1:0]  rresp;
    wire        rvalid;
    reg         rready = 1'b1;

    wire [3:0] vgaRed;
    wire [3:0] vgaGreen;
    wire [3:0] vgaBlue;
    wire       Hsync;
    wire       Vsync;

    integer hsync_low_pixels;
    reg [31:0] rd;

    always #5 clk = ~clk; // 100MHz

    vga_axi #(
        .FONT_MEM_FILE(FONT_MEM_FILE)
    ) dut(
        .vgaRed(vgaRed),
        .vgaGreen(vgaGreen),
        .vgaBlue(vgaBlue),
        .Hsync(Hsync),
        .Vsync(Vsync),
        .S_AXI_ACLK(clk),
        .S_AXI_ARESETN(resetn),
        .S_AXI_AWADDR(awaddr),
        .S_AXI_AWVALID(awvalid),
        .S_AXI_AWREADY(awready),
        .S_AXI_WDATA(wdata),
        .S_AXI_WSTRB(wstrb),
        .S_AXI_WVALID(wvalid),
        .S_AXI_WREADY(wready),
        .S_AXI_BRESP(bresp),
        .S_AXI_BVALID(bvalid),
        .S_AXI_BREADY(bready),
        .S_AXI_ARADDR(araddr),
        .S_AXI_ARVALID(arvalid),
        .S_AXI_ARREADY(arready),
        .S_AXI_RDATA(rdata),
        .S_AXI_RRESP(rresp),
        .S_AXI_RVALID(rvalid),
        .S_AXI_RREADY(rready)
    );

    task axi_write;
        input [5:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);
            awaddr  <= addr;
            wdata   <= data;
            awvalid <= 1'b1;
            wvalid  <= 1'b1;
            wait (awready && wready);
            @(posedge clk);
            awvalid <= 1'b0;
            wvalid  <= 1'b0;
            wait (bvalid);
            if (bresp != 2'b00) begin
                $display("FAIL: AXI write response is not OKAY");
                $finish;
            end
            @(posedge clk);
        end
    endtask

    task axi_read;
        input [5:0] addr;
        output [31:0] data;
        begin
            @(posedge clk);
            araddr  <= addr;
            arvalid <= 1'b1;
            wait (arready);
            @(posedge clk);
            arvalid <= 1'b0;
            wait (rvalid);
            data = rdata;
            if (rresp != 2'b00) begin
                $display("FAIL: AXI read response is not OKAY");
                $finish;
            end
            @(posedge clk);
        end
    endtask

    task vga_write_char;
        input [10:0] addr;
        input [7:0] ch;
        begin
            axi_write(6'h04, {21'd0, addr});
            axi_write(6'h08, {24'd0, ch});
            axi_write(6'h0C, 32'h0000_0001);
        end
    endtask

    task vga_write_canvas;
        input [9:0] addr;
        input bit_value;
        begin
            axi_write(6'h18, {22'd0, addr});
            axi_write(6'h1C, {31'd0, bit_value});
            axi_write(6'h20, 32'h0000_0001);
        end
    endtask

    task wait_pixel;
        input [9:0] x;
        input [9:0] y;
        begin
            while (!(dut.u_vga_ctrl.pix_phase == 2'd3 &&
                     dut.u_vga_ctrl.h_cnt == x &&
                     dut.u_vga_ctrl.v_cnt == y)) begin
                @(posedge clk);
            end
            @(posedge clk);
        end
    endtask

    initial begin
        repeat (10) @(posedge clk);
        resetn <= 1'b1;
        repeat (10) @(posedge clk);

        axi_read(6'h00, rd);
        if (rd[0] !== 1'b1) begin
            $display("FAIL: VGA enable reset value mismatch. ctrl=%h", rd);
            $finish;
        end

        vga_write_char(11'd0, "H");
        vga_write_char(11'd1, "I");
        repeat (4) @(posedge clk);

        if (dut.u_vga_ctrl.char_buf[0] !== "H" ||
            dut.u_vga_ctrl.char_buf[1] !== "I") begin
            $display("FAIL: char buffer write mismatch. char0=%h char1=%h",
                     dut.u_vga_ctrl.char_buf[0], dut.u_vga_ctrl.char_buf[1]);
            $finish;
        end

        vga_write_canvas(10'd0, 1'b1);
        repeat (4) @(posedge clk);
        if (dut.u_vga_ctrl.canvas_buf[0] !== 1'b1) begin
            $display("FAIL: canvas buffer write mismatch");
            $finish;
        end

        axi_write(6'h00, 32'h0000_0003); // enable + clear pulse
        wait (dut.u_vga_ctrl.clear_busy == 1'b1);
        wait (dut.u_vga_ctrl.clear_busy == 1'b0);
        repeat (4) @(posedge clk);
        if (dut.u_vga_ctrl.char_buf[0] !== 8'h20 ||
            dut.u_vga_ctrl.char_buf[1199] !== 8'h20) begin
            $display("FAIL: clear did not fill char buffer with spaces");
            $finish;
        end

        vga_write_char(11'd0, "A");
        vga_write_canvas(10'd0, 1'b1);
        axi_write(6'h24, 32'h0000_0001); // canvas_mode = 1
        axi_read(6'h24, rd);
        if (rd[0] !== 1'b1) begin
            $display("FAIL: canvas_mode readback mismatch");
            $finish;
        end

        wait_pixel(10'd799, 10'd0);
        @(posedge clk);
        if (dut.u_vga_ctrl.h_cnt !== 10'd0 || dut.u_vga_ctrl.v_cnt !== 10'd1) begin
            $display("FAIL: VGA line rollover mismatch. h=%0d v=%0d",
                     dut.u_vga_ctrl.h_cnt, dut.u_vga_ctrl.v_cnt);
            $finish;
        end

        hsync_low_pixels = 0;
        wait_pixel(10'd0, 10'd2);
        while (dut.u_vga_ctrl.v_cnt == 10'd2) begin
            if (dut.u_vga_ctrl.pix_phase == 2'd3 && Hsync == 1'b0)
                hsync_low_pixels = hsync_low_pixels + 1;
            @(posedge clk);
        end

        if (hsync_low_pixels != 96) begin
            $display("FAIL: Hsync low width mismatch. got=%0d expected=96", hsync_low_pixels);
            $finish;
        end

        $display("PASS: tb_vga_axi completed");
        $finish;
    end

endmodule
