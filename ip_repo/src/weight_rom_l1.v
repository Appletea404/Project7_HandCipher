`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/29/2026 11:14:32 AM
// Design Name: 
// Module Name: weight_rom_l1
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


module weight_rom_l1 (
    input wire          clk,
    input wire [15:0]   addr,   // 0 ~ 50175
    output reg signed [7:0] data
);
    (* rom_style = "block" *) reg signed [7:0] mem[0:50175];

    initial begin
        $readmemh("weights_l1.mem", mem);
    end

    always @(posedge clk) begin
        data <= mem[addr];
    end
endmodule