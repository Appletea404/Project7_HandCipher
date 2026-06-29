`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/29/2026 11:14:53 AM
// Design Name: 
// Module Name: bias_rom_l1
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


module bias_rom_l1 (
    input wire          clk,
    input wire [5:0]    addr,   // 0 ~ 63
    output reg signed [31:0] data
);
    (* rom_style = "block" *) reg signed [31:0] mem[0:63];

    initial begin
        $readmemh("biases_l1.mem", mem);
    end

    always @(posedge clk) begin
        data <= mem[addr];
    end
endmodule