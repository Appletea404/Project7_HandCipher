`timescale 1ns / 1ps



module vga_ctrl(
    input wire clk,
    input wire reset_p

    );

    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            // clk <= 0;
        end
        else if (clk)begin
            
        end
    end
endmodule
