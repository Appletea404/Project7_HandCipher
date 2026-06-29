`timescale 1ns / 1ps

module font_rom #(
    parameter FONT_MEM_FILE = "font_rom.mem"
)(
    input  wire        clk,
    input  wire [10:0] addr,  // 0~2047: 128 ASCII chars * 16 rows
    output reg  [15:0] data   // one 16-pixel glyph row, bit15 = leftmost pixel
    );

    (* rom_style = "block" *) reg [15:0] mem [0:2047];

    initial begin
        $readmemh(FONT_MEM_FILE, mem);
    end

    always @(posedge clk) begin
        data <= mem[addr];
    end

endmodule
