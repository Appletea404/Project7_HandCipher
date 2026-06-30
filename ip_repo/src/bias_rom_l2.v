`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/29/2026 11:15:32 AM
// Design Name: 
// Module Name: bias_rom_l2
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


module bias_rom_l2 (
    input wire          clk,
    input wire [4:0]    addr,   // 0 ~ 25
    output reg signed [31:0] data
);
    (* rom_style = "block" *) reg signed [31:0] mem[0:25];

    initial begin
        $readmemh("biases_l2.mem", mem);
    end

    always @(posedge clk) begin
        data <= mem[addr];
    end
endmodule