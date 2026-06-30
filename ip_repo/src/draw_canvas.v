`timescale 1ns / 1ps

module draw_canvas(
    input  wire       clk,
    input  wire       reset_p,
    input  wire       enable,
    input  wire       clear_req,

    input  wire       PenIrq_n,
    output wire       DCLK,
    output wire       DIN,
    input  wire       DOUT,
    output wire       CS_N,

    output reg  [9:0] canvas_wr_addr,
    output reg        canvas_wr_data,
    output reg        canvas_wr_en,

    output wire [11:0] touch_x_raw,
    output wire [11:0] touch_y_raw,
    output reg         touch_valid_pulse,
    output reg         btn_ok_pulse,
    output reg         btn_clear_pulse,
    output reg         clear_busy
    );

    wire rst_n = ~reset_p;
    wire [11:0] x_value;
    wire [11:0] y_value;
    wire get_flag;

    // IP_TEST에서 가장 안정적이었던 터치 설정을 그대로 사용한다.
    xpt2046 #(
        .CONV_TIMES(20),
        .FILTER_PARAM(3),
        .CNT_TOP(21'd1499999),
        .DCLK_DIV_TOP(6'd49)
    ) touch_pad(
        clk, rst_n, enable,
        x_value, y_value, get_flag,
        PenIrq_n, DCLK, DIN, DOUT, CS_N
    );

    assign touch_x_raw = x_value;
    assign touch_y_raw = y_value;

    wire [11:0] x_tmp = (x_value > 12'd300) ? (x_value - 12'd300) : 12'd0;
    wire [11:0] y_tmp = (y_value > 12'd300) ? (y_value - 12'd300) : 12'd0;

    wire [15:0] touch_x_scaled = ((x_tmp * 32'd70) >> 10);
    wire [15:0] touch_y_320    = ((y_tmp * 32'd94) >> 10);
    wire [15:0] touch_y_scaled = (16'd319 > touch_y_320) ? (16'd319 - touch_y_320) : 16'd0;

    wire [15:0] touch_x_clamped = (touch_x_scaled > 16'd239) ? 16'd239 : touch_x_scaled;
    wire [15:0] touch_y_clamped = (touch_y_scaled > 16'd319) ? 16'd319 : touch_y_scaled;

    // LCD 표시 x를 반전했기 때문에 터치 x도 같은 화면 좌표계로 반전한다.
    wire [15:0] touch_x_screen = 16'd239 - touch_x_clamped;
    wire [15:0] touch_y_screen = touch_y_clamped;

    reg [15:0] touch_x_latched;
    reg [15:0] touch_y_latched;
    reg        touch_pending;
    reg        touch_sample_valid;

    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            touch_x_latched   <= 16'd0;
            touch_y_latched   <= 16'd0;
            touch_pending     <= 1'b0;
            touch_sample_valid<= 1'b0;
        end
        else begin
            touch_sample_valid <= touch_pending;
            touch_pending      <= 1'b0;

            if (enable && get_flag && !PenIrq_n) begin
                touch_x_latched <= touch_x_screen;
                touch_y_latched <= touch_y_screen;
                touch_pending   <= 1'b1;
            end
        end
    end

    wire in_canvas_grid_touch = (touch_x_latched >= 16'd8 && touch_x_latched < 16'd232 &&
                                 touch_y_latched >= 16'd8 && touch_y_latched < 16'd232);
    wire in_button_area_touch = (touch_y_latched >= 16'd240);
    wire touch_ok_button      = in_button_area_touch && (touch_x_latched < 16'd120);
    wire touch_clear_button   = in_button_area_touch && (touch_x_latched >= 16'd120);

    wire [4:0] grid_x_touch = (touch_x_latched - 16'd8) >> 3;
    wire [4:0] grid_y_touch = (touch_y_latched - 16'd8) >> 3;

    reg [9:0] clear_addr;

    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            canvas_wr_addr    <= 10'd0;
            canvas_wr_data    <= 1'b0;
            canvas_wr_en      <= 1'b0;
            touch_valid_pulse <= 1'b0;
            btn_ok_pulse      <= 1'b0;
            btn_clear_pulse   <= 1'b0;
            clear_busy        <= 1'b0;
            clear_addr        <= 10'd0;
        end
        else begin
            canvas_wr_en      <= 1'b0;
            touch_valid_pulse <= 1'b0;
            btn_ok_pulse      <= 1'b0;
            btn_clear_pulse   <= 1'b0;

            if (clear_busy) begin
                canvas_wr_addr <= clear_addr;
                canvas_wr_data <= 1'b0;
                canvas_wr_en   <= 1'b1;

                if (clear_addr >= 10'd783) begin
                    clear_addr <= 10'd0;
                    clear_busy <= 1'b0;
                end
                else begin
                    clear_addr <= clear_addr + 1'b1;
                end
            end
            else if (clear_req || (touch_sample_valid && touch_clear_button)) begin
                btn_clear_pulse <= touch_sample_valid && touch_clear_button;
                clear_addr      <= 10'd0;
                clear_busy      <= 1'b1;
            end
            else if (touch_sample_valid && touch_ok_button) begin
                btn_ok_pulse <= 1'b1;
            end
            else if (touch_sample_valid && in_canvas_grid_touch) begin
                canvas_wr_addr    <= (grid_y_touch * 10'd28) + grid_x_touch;
                canvas_wr_data    <= 1'b1;
                canvas_wr_en      <= 1'b1;
                touch_valid_pulse <= 1'b1;
            end
        end
    end

endmodule
