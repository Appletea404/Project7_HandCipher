`timescale 1ns / 1ps

module tft_axi #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 6
)(
    input  wire       tft_sdo,
    output wire       tft_sck,
    output wire       tft_sdi,
    output wire       tft_dc,
    output wire       tft_reset,
    output wire       tft_cs,

    input  wire       PenIrq_n,
    output wire       DCLK,
    output wire       DIN,
    input  wire       DOUT,
    output wire       CS_N,

    // TOP 통합 시 NPU와 공유할 외부 Canvas BRAM Port A write 신호다.
    output wire [9:0] canvas_addra,
    output wire       canvas_dina,
    output wire       canvas_wea,
    output wire       canvas_ena,

    input  wire                                  S_AXI_ACLK,
    input  wire                                  S_AXI_ARESETN,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]         S_AXI_AWADDR,
    input  wire                                  S_AXI_AWVALID,
    output wire                                  S_AXI_AWREADY,
    input  wire [C_S_AXI_DATA_WIDTH-1:0]         S_AXI_WDATA,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0]     S_AXI_WSTRB,
    input  wire                                  S_AXI_WVALID,
    output wire                                  S_AXI_WREADY,
    output wire [1:0]                            S_AXI_BRESP,
    output wire                                  S_AXI_BVALID,
    input  wire                                  S_AXI_BREADY,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]         S_AXI_ARADDR,
    input  wire                                  S_AXI_ARVALID,
    output wire                                  S_AXI_ARREADY,
    output wire [C_S_AXI_DATA_WIDTH-1:0]         S_AXI_RDATA,
    output wire [1:0]                            S_AXI_RRESP,
    output wire                                  S_AXI_RVALID,
    input  wire                                  S_AXI_RREADY
    );

    localparam ADDR_CTRL           = 4'd0; // 0x00
    localparam ADDR_TOUCH_X        = 4'd1; // 0x04
    localparam ADDR_TOUCH_Y        = 4'd2; // 0x08
    localparam ADDR_STATUS         = 4'd3; // 0x0C
    localparam ADDR_CANVAS_RD_ADDR = 4'd4; // 0x10
    localparam ADDR_CANVAS_RD_DATA = 4'd5; // 0x14

    reg                                  axi_awready;
    reg                                  axi_wready;
    reg                                  axi_bvalid;
    reg                                  axi_arready;
    reg [C_S_AXI_DATA_WIDTH-1:0]         axi_rdata;
    reg                                  axi_rvalid;

    reg                                  reg_enable;
    reg [9:0]                            reg_canvas_rd_addr;
    reg                                  clear_pulse;
    reg                                  btn_ok_sticky;
    reg                                  btn_clear_sticky;
    reg                                  touch_valid_sticky;

    wire [3:0]                           wr_addr_word = S_AXI_AWADDR[5:2];
    wire [3:0]                           rd_addr_word = S_AXI_ARADDR[5:2];
    wire                                 write_fire = S_AXI_AWVALID && S_AXI_WVALID &&
                                                       !axi_awready && !axi_wready && !axi_bvalid;
    wire                                 read_fire  = S_AXI_ARVALID && !axi_arready && !axi_rvalid;
    wire                                 status_read_fire = read_fire && (rd_addr_word == ADDR_STATUS);

    wire [11:0]                          touch_x_raw;
    wire [11:0]                          touch_y_raw;
    wire                                 touch_valid_pulse;
    wire                                 btn_ok_pulse;
    wire                                 btn_clear_pulse;
    wire                                 clear_busy;
    wire [9:0]                           touch_wr_addr;
    wire                                 touch_wr_data;
    wire                                 touch_wr_en;

    wire [9:0]                           display_rd_addr;
    reg                                  display_rd_data;
    reg                                  cpu_rd_data;

    (* ram_style = "distributed" *) reg canvas_mem [0:783];

    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY  = axi_wready;
    assign S_AXI_BRESP   = 2'b00;
    assign S_AXI_BVALID  = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RDATA   = axi_rdata;
    assign S_AXI_RRESP   = 2'b00;
    assign S_AXI_RVALID  = axi_rvalid;

    assign canvas_addra = touch_wr_addr;
    assign canvas_dina  = touch_wr_data;
    assign canvas_wea   = touch_wr_en;
    assign canvas_ena   = 1'b1;

    integer i;

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            display_rd_data <= 1'b0;
            cpu_rd_data     <= 1'b0;
        end
        else begin
            display_rd_data <= canvas_mem[display_rd_addr];
            cpu_rd_data     <= canvas_mem[reg_canvas_rd_addr];
        end
    end

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_awready        <= 1'b0;
            axi_wready         <= 1'b0;
            axi_bvalid         <= 1'b0;
            reg_enable         <= 1'b1;
            reg_canvas_rd_addr <= 10'd0;
            clear_pulse        <= 1'b0;
            btn_ok_sticky      <= 1'b0;
            btn_clear_sticky   <= 1'b0;
            touch_valid_sticky <= 1'b0;

            for (i = 0; i < 784; i = i + 1)
                canvas_mem[i] <= 1'b0;
        end
        else begin
            axi_awready <= 1'b0;
            axi_wready  <= 1'b0;
            clear_pulse <= 1'b0;

            if (status_read_fire) begin
                touch_valid_sticky <= 1'b0;
                btn_ok_sticky      <= 1'b0;
                btn_clear_sticky   <= 1'b0;
            end

            if (touch_wr_en)
                canvas_mem[touch_wr_addr] <= touch_wr_data;

            if (touch_valid_pulse)
                touch_valid_sticky <= 1'b1;
            if (btn_ok_pulse)
                btn_ok_sticky <= 1'b1;
            if (btn_clear_pulse)
                btn_clear_sticky <= 1'b1;

            if (write_fire) begin
                axi_awready <= 1'b1;
                axi_wready  <= 1'b1;
                axi_bvalid  <= 1'b1;

                case (wr_addr_word)
                    ADDR_CTRL: begin
                        if (S_AXI_WSTRB[0]) begin
                            reg_enable  <= S_AXI_WDATA[0];
                            clear_pulse <= S_AXI_WDATA[1];
                        end
                    end
                    ADDR_CANVAS_RD_ADDR: begin
                        if (S_AXI_WSTRB[0] || S_AXI_WSTRB[1])
                            reg_canvas_rd_addr <= (S_AXI_WDATA[9:0] < 10'd784) ? S_AXI_WDATA[9:0] : 10'd783;
                    end
                    default: begin
                    end
                endcase
            end
            else if (S_AXI_BREADY && axi_bvalid) begin
                axi_bvalid <= 1'b0;
            end
        end
    end

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_arready <= 1'b0;
            axi_rdata   <= 32'h0;
            axi_rvalid  <= 1'b0;
        end
        else begin
            axi_arready <= 1'b0;

            if (read_fire) begin
                axi_arready <= 1'b1;
                axi_rvalid  <= 1'b1;

                case (rd_addr_word)
                    ADDR_CTRL:           axi_rdata <= {30'd0, clear_busy, reg_enable};
                    ADDR_TOUCH_X:        axi_rdata <= {20'd0, touch_x_raw};
                    ADDR_TOUCH_Y:        axi_rdata <= {20'd0, touch_y_raw};
                    ADDR_STATUS: begin
                        axi_rdata <= {28'd0, btn_clear_sticky, btn_ok_sticky, 1'b1, touch_valid_sticky};
                    end
                    ADDR_CANVAS_RD_ADDR: axi_rdata <= {22'd0, reg_canvas_rd_addr};
                    ADDR_CANVAS_RD_DATA: axi_rdata <= {31'd0, cpu_rd_data};
                    default:             axi_rdata <= 32'hDEAD_BEEF;
                endcase
            end
            else if (S_AXI_RREADY && axi_rvalid) begin
                axi_rvalid <= 1'b0;
            end
        end
    end

    draw_canvas u_draw_canvas(
        .clk(S_AXI_ACLK),
        .reset_p(!S_AXI_ARESETN),
        .enable(reg_enable),
        .clear_req(clear_pulse),
        .PenIrq_n(PenIrq_n),
        .DCLK(DCLK),
        .DIN(DIN),
        .DOUT(DOUT),
        .CS_N(CS_N),
        .canvas_wr_addr(touch_wr_addr),
        .canvas_wr_data(touch_wr_data),
        .canvas_wr_en(touch_wr_en),
        .touch_x_raw(touch_x_raw),
        .touch_y_raw(touch_y_raw),
        .touch_valid_pulse(touch_valid_pulse),
        .btn_ok_pulse(btn_ok_pulse),
        .btn_clear_pulse(btn_clear_pulse),
        .clear_busy(clear_busy)
    );

    canvas_display u_canvas_display(
        .clk(S_AXI_ACLK),
        .reset_p(!S_AXI_ARESETN),
        .tft_sdo(tft_sdo),
        .tft_sck(tft_sck),
        .tft_sdi(tft_sdi),
        .tft_dc(tft_dc),
        .tft_reset(tft_reset),
        .tft_cs(tft_cs),
        .canvas_rd_addr(display_rd_addr),
        .canvas_rd_data(display_rd_data)
    );

endmodule
