`timescale 1ns / 1ps

// VGA 단독 보드 테스트용 임시 top.
// PLAN.md의 CONFIRMING 화면 예시를 AXI/MicroBlaze 없이 고정 출력한다.
module vga_test_top(
    input  wire       clk,        // Basys3 100MHz: W5
    input  wire       reset_p,    // btnC active-high: U18

    output wire [3:0] vgaRed,
    output wire [3:0] vgaGreen,
    output wire [3:0] vgaBlue,
    output wire       Hsync,
    output wire       Vsync
    );

    reg         enable = 1'b1;
    reg         clear = 1'b0;
    reg         canvas_mode = 1'b1;

    reg [10:0]  char_wr_addr = 11'd0;
    reg [7:0]   char_wr_data = 8'h20;
    reg         char_wr_en = 1'b0;

    reg [9:0]   canvas_wr_addr = 10'd0;
    reg         canvas_wr_data = 1'b0;
    reg         canvas_wr_en = 1'b0;

    wire        clear_busy;

    wire [11:0] fg_color = 12'h0F0; // green text
    wire [11:0] bg_color = 12'h000; // black background

    vga_ctrl u_vga_ctrl(
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

    localparam ST_CLEAR_PULSE  = 3'd0;
    localparam ST_WAIT_CLEAR_1 = 3'd1;
    localparam ST_WAIT_CLEAR_0 = 3'd2;
    localparam ST_WRITE_TEXT   = 3'd3;
    localparam ST_WRITE_CANVAS = 3'd4;
    localparam ST_DONE         = 3'd5;

    reg [2:0]  state = ST_CLEAR_PULSE;
    reg [3:0]  msg_idx = 4'd0;
    reg [6:0]  char_idx = 7'd0;
    reg [9:0]  canvas_idx = 10'd0;
    reg [4:0]  canvas_x = 5'd0;
    reg [4:0]  canvas_y = 5'd0;

    function [10:0] row_col;
        input [5:0] row;
        input [6:0] col;
        begin
            // vga_ctrl이 16x16 확대 문자 모드이므로 1줄은 40글자다.
            row_col = ({6'd0, row} << 5) + ({6'd0, row} << 3) + {4'd0, col};
        end
    endfunction

    function [10:0] msg_base;
        input [3:0] msg;
        begin
            case (msg)
                4'd0: msg_base = row_col(6'd0,  7'd0);  // === CAESAR CIPHER SYSTEM ===
                4'd1: msg_base = row_col(6'd2,  7'd0);  // MODE: ENCRYPT   SHIFT: +3
                4'd2: msg_base = row_col(6'd5,  7'd17); // NPU Result : B
                4'd3: msg_base = row_col(6'd8,  7'd17); // btnC = CONFIRM
                4'd4: msg_base = row_col(6'd10, 7'd17); // btnL = RETRY
                4'd5: msg_base = row_col(6'd22, 7'd0);  // Plaintext  : APPLE
                4'd6: msg_base = row_col(6'd23, 7'd0);  // Ciphertext : DSSOH
                4'd7: msg_base = row_col(6'd29, 7'd0);  // C=OK L=CLR SW=SHIFT MODE
                default: msg_base = 11'd0;
            endcase
        end
    endfunction

    function [6:0] msg_len;
        input [3:0] msg;
        begin
            case (msg)
                4'd0: msg_len = 7'd28;
                4'd1: msg_len = 7'd26;
                4'd2: msg_len = 7'd14;
                4'd3: msg_len = 7'd14;
                4'd4: msg_len = 7'd12;
                4'd5: msg_len = 7'd18;
                4'd6: msg_len = 7'd18;
                4'd7: msg_len = 7'd24;
                default: msg_len = 7'd0;
            endcase
        end
    endfunction

    function [7:0] msg_char;
        input [3:0] msg;
        input [6:0] idx;
        begin
            msg_char = 8'h20;
            case (msg)
                // "=== CAESAR CIPHER SYSTEM ==="
                4'd0: begin
                    case (idx)
                        7'd0: msg_char="="; 7'd1: msg_char="="; 7'd2: msg_char="="; 7'd3: msg_char=" ";
                        7'd4: msg_char="C"; 7'd5: msg_char="A"; 7'd6: msg_char="E"; 7'd7: msg_char="S"; 7'd8: msg_char="A"; 7'd9: msg_char="R";
                        7'd10: msg_char=" "; 7'd11: msg_char="C"; 7'd12: msg_char="I"; 7'd13: msg_char="P"; 7'd14: msg_char="H"; 7'd15: msg_char="E"; 7'd16: msg_char="R";
                        7'd17: msg_char=" "; 7'd18: msg_char="S"; 7'd19: msg_char="Y"; 7'd20: msg_char="S"; 7'd21: msg_char="T"; 7'd22: msg_char="E"; 7'd23: msg_char="M";
                        7'd24: msg_char=" "; 7'd25: msg_char="="; 7'd26: msg_char="="; 7'd27: msg_char="=";
                    endcase
                end

                // "MODE: ENCRYPT   SHIFT: +3"
                4'd1: begin
                    case (idx)
                        7'd0: msg_char="M"; 7'd1: msg_char="O"; 7'd2: msg_char="D"; 7'd3: msg_char="E"; 7'd4: msg_char=":"; 7'd5: msg_char=" ";
                        7'd6: msg_char="E"; 7'd7: msg_char="N"; 7'd8: msg_char="C"; 7'd9: msg_char="R"; 7'd10: msg_char="Y"; 7'd11: msg_char="P"; 7'd12: msg_char="T";
                        7'd13: msg_char=" "; 7'd14: msg_char=" "; 7'd15: msg_char=" ";
                        7'd16: msg_char="S"; 7'd17: msg_char="H"; 7'd18: msg_char="I"; 7'd19: msg_char="F"; 7'd20: msg_char="T"; 7'd21: msg_char=":";
                        7'd22: msg_char=" "; 7'd23: msg_char="+"; 7'd24: msg_char="3";
                    endcase
                end

                // "NPU Result : B"
                4'd2: begin
                    case (idx)
                        7'd0: msg_char="N"; 7'd1: msg_char="P"; 7'd2: msg_char="U"; 7'd3: msg_char=" ";
                        7'd4: msg_char="R"; 7'd5: msg_char="e"; 7'd6: msg_char="s"; 7'd7: msg_char="u"; 7'd8: msg_char="l"; 7'd9: msg_char="t";
                        7'd10: msg_char=" "; 7'd11: msg_char=":"; 7'd12: msg_char=" "; 7'd13: msg_char="B";
                    endcase
                end

                // "btnC = CONFIRM"
                4'd3: begin
                    case (idx)
                        7'd0: msg_char="b"; 7'd1: msg_char="t"; 7'd2: msg_char="n"; 7'd3: msg_char="C"; 7'd4: msg_char=" "; 7'd5: msg_char="="; 7'd6: msg_char=" ";
                        7'd7: msg_char="C"; 7'd8: msg_char="O"; 7'd9: msg_char="N"; 7'd10: msg_char="F"; 7'd11: msg_char="I"; 7'd12: msg_char="R"; 7'd13: msg_char="M";
                    endcase
                end

                // "btnL = RETRY"
                4'd4: begin
                    case (idx)
                        7'd0: msg_char="b"; 7'd1: msg_char="t"; 7'd2: msg_char="n"; 7'd3: msg_char="L"; 7'd4: msg_char=" "; 7'd5: msg_char="="; 7'd6: msg_char=" ";
                        7'd7: msg_char="R"; 7'd8: msg_char="E"; 7'd9: msg_char="T"; 7'd10: msg_char="R"; 7'd11: msg_char="Y";
                    endcase
                end

                // "Plaintext  : APPLE"
                4'd5: begin
                    case (idx)
                        7'd0: msg_char="P"; 7'd1: msg_char="l"; 7'd2: msg_char="a"; 7'd3: msg_char="i"; 7'd4: msg_char="n"; 7'd5: msg_char="t"; 7'd6: msg_char="e"; 7'd7: msg_char="x"; 7'd8: msg_char="t";
                        7'd9: msg_char=" "; 7'd10: msg_char=" "; 7'd11: msg_char=":"; 7'd12: msg_char=" ";
                        7'd13: msg_char="A"; 7'd14: msg_char="P"; 7'd15: msg_char="P"; 7'd16: msg_char="L"; 7'd17: msg_char="E";
                    endcase
                end

                // "Ciphertext : DSSOH"
                4'd6: begin
                    case (idx)
                        7'd0: msg_char="C"; 7'd1: msg_char="i"; 7'd2: msg_char="p"; 7'd3: msg_char="h"; 7'd4: msg_char="e"; 7'd5: msg_char="r"; 7'd6: msg_char="t"; 7'd7: msg_char="e"; 7'd8: msg_char="x"; 7'd9: msg_char="t";
                        7'd10: msg_char=" "; 7'd11: msg_char=":"; 7'd12: msg_char=" ";
                        7'd13: msg_char="D"; 7'd14: msg_char="S"; 7'd15: msg_char="S"; 7'd16: msg_char="O"; 7'd17: msg_char="H";
                    endcase
                end

                // "C=OK L=CLR SW=SHIFT MODE"
                4'd7: begin
                    case (idx)
                        7'd0: msg_char="C"; 7'd1: msg_char="="; 7'd2: msg_char="O"; 7'd3: msg_char="K"; 7'd4: msg_char=" ";
                        7'd5: msg_char="L"; 7'd6: msg_char="="; 7'd7: msg_char="C"; 7'd8: msg_char="L"; 7'd9: msg_char="R"; 7'd10: msg_char=" ";
                        7'd11: msg_char="S"; 7'd12: msg_char="W"; 7'd13: msg_char="="; 7'd14: msg_char="S"; 7'd15: msg_char="H"; 7'd16: msg_char="I"; 7'd17: msg_char="F"; 7'd18: msg_char="T"; 7'd19: msg_char=" ";
                        7'd20: msg_char="M"; 7'd21: msg_char="O"; 7'd22: msg_char="D"; 7'd23: msg_char="E";
                    endcase
                end
            endcase
        end
    endfunction

    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            state          <= ST_CLEAR_PULSE;
            clear          <= 1'b0;
            char_wr_en     <= 1'b0;
            canvas_wr_en   <= 1'b0;
            msg_idx        <= 4'd0;
            char_idx       <= 7'd0;
            canvas_idx     <= 10'd0;
            canvas_x       <= 5'd0;
            canvas_y       <= 5'd0;
            canvas_mode    <= 1'b1;
            enable         <= 1'b1;
        end
        else begin
            clear        <= 1'b0;
            char_wr_en   <= 1'b0;
            canvas_wr_en <= 1'b0;

            case (state)
                ST_CLEAR_PULSE: begin
                    clear <= 1'b1;
                    state <= ST_WAIT_CLEAR_1;
                end

                // clear_busy가 실제로 올라온 것을 본 뒤에야 clear 종료를 기다린다.
                ST_WAIT_CLEAR_1: begin
                    if (clear_busy)
                        state <= ST_WAIT_CLEAR_0;
                end

                ST_WAIT_CLEAR_0: begin
                    if (!clear_busy)
                        state <= ST_WRITE_TEXT;
                end

                ST_WRITE_TEXT: begin
                    char_wr_en   <= 1'b1;
                    char_wr_addr <= msg_base(msg_idx) + {4'd0, char_idx};
                    char_wr_data <= msg_char(msg_idx, char_idx);

                    if (char_idx == (msg_len(msg_idx) - 7'd1)) begin
                        char_idx <= 7'd0;
                        if (msg_idx == 4'd7)
                            state <= ST_WRITE_CANVAS;
                        else
                            msg_idx <= msg_idx + 4'd1;
                    end
                    else begin
                        char_idx <= char_idx + 7'd1;
                    end
                end

                ST_WRITE_CANVAS: begin
                    canvas_wr_en   <= 1'b1;
                    canvas_wr_addr <= canvas_idx;

                    // 28x28 영역에 X 모양 + 테두리. PLAN.md의 손글씨 프리뷰 자리 확인용.
                    canvas_wr_data <= (canvas_x == canvas_y) ||
                                      (canvas_x + canvas_y == 5'd27) ||
                                      (canvas_x == 5'd0) || (canvas_x == 5'd27) ||
                                      (canvas_y == 5'd0) || (canvas_y == 5'd27);

                    if (canvas_idx == 10'd783) begin
                        canvas_idx <= 10'd0;
                        canvas_x   <= 5'd0;
                        canvas_y   <= 5'd0;
                        state      <= ST_DONE;
                    end
                    else begin
                        canvas_idx <= canvas_idx + 10'd1;
                        if (canvas_x == 5'd27) begin
                            canvas_x <= 5'd0;
                            canvas_y <= canvas_y + 5'd1;
                        end
                        else begin
                            canvas_x <= canvas_x + 5'd1;
                        end
                    end
                end

                ST_DONE: begin
                    state <= ST_DONE;
                end

                default: begin
                    state <= ST_CLEAR_PULSE;
                end
            endcase
        end
    end

endmodule
