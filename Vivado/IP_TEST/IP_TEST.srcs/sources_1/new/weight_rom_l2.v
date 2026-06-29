`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/29/2026 11:15:12 AM
// Design Name: 
// Module Name: weight_rom_l2
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module weight_rom_l2 (
    input wire          clk,
    input wire [10:0]   addr,   // 0 ~ 1663
    output reg signed [7:0] data
);
    (* rom_style = "block" *) reg signed [7:0] mem[0:1663];

    initial begin
        $readmemh("weights_l2.mem", mem);
    end

    always @(posedge clk) begin
        data <= mem[addr];
    end
endmodule