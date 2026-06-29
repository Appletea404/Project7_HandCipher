`timescale 1ns / 1ps

module tb_font_rom;

    reg         clk = 1'b0;
    reg [10:0] addr = 11'd0;   // 0~2047 (128 chars * 16 rows)
    wire [15:0] data;          // one 16-pixel glyph row

    localparam FONT_MEM_FILE = "/home/appletea/workspace_onedevice_2/Project_7_HandCipher/Vivado/IP_TEST/IP_TEST.srcs/sources_1/new/font_rom.mem";

    font_rom #(
        .FONT_MEM_FILE(FONT_MEM_FILE)
    ) uut(
        .clk(clk),
        .addr(addr),
        .data(data)
    );

    always #5 clk = ~clk;

    integer row;

    initial begin
        // 'A' = ASCII 65, addr = 65*16 = 1040~1055
        for (row = 0; row < 16; row = row + 1) begin
            @(posedge clk);
            addr <= 11'd1040 + row[10:0];
        end

        repeat (4) @(posedge clk);
        $finish;
    end

endmodule
