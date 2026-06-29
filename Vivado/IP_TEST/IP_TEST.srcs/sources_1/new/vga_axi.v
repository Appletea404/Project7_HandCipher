`timescale 1ns / 1ps

module vga_axi #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 6
)(
    output wire [3:0] vgaRed,
    output wire [3:0] vgaGreen,
    output wire [3:0] vgaBlue,
    output wire       Hsync,
    output wire       Vsync,

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
    localparam ADDR_CHAR_ADDR      = 4'd1; // 0x04
    localparam ADDR_CHAR_DATA      = 4'd2; // 0x08
    localparam ADDR_WR_STRB        = 4'd3; // 0x0C
    localparam ADDR_FG_COLOR       = 4'd4; // 0x10
    localparam ADDR_BG_COLOR       = 4'd5; // 0x14
    localparam ADDR_CANVAS_WR_ADDR = 4'd6; // 0x18
    localparam ADDR_CANVAS_WR_DATA = 4'd7; // 0x1C
    localparam ADDR_CANVAS_WR_EN   = 4'd8; // 0x20
    localparam ADDR_CANVAS_MODE    = 4'd9; // 0x24

    reg                                  axi_awready;
    reg                                  axi_wready;
    reg                                  axi_bvalid;
    reg                                  axi_arready;
    reg [C_S_AXI_DATA_WIDTH-1:0]         axi_rdata;
    reg                                  axi_rvalid;

    reg                                  reg_enable;
    reg [10:0]                           reg_char_addr;
    reg [7:0]                            reg_char_data;
    reg [11:0]                           reg_fg_color;
    reg [11:0]                           reg_bg_color;
    reg [9:0]                            reg_canvas_wr_addr;
    reg                                  reg_canvas_wr_data;
    reg                                  reg_canvas_mode;

    reg                                  clear_pulse;
    reg                                  char_wr_pulse;
    reg                                  canvas_wr_pulse;

    wire                                 clear_busy;
    wire [3:0]                           wr_addr_word = S_AXI_AWADDR[5:2];
    wire [3:0]                           rd_addr_word = S_AXI_ARADDR[5:2];
    // AXI 응답이 아직 남아있을 때 다음 요청을 받지 않도록 한 번에 한 트랜잭션만 처리한다.
    wire                                 write_fire = S_AXI_AWVALID && S_AXI_WVALID &&
                                                       !axi_awready && !axi_wready && !axi_bvalid;
    wire                                 read_fire  = S_AXI_ARVALID && !axi_arready && !axi_rvalid;

    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY  = axi_wready;
    assign S_AXI_BRESP   = 2'b00;
    assign S_AXI_BVALID  = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RDATA   = axi_rdata;
    assign S_AXI_RRESP   = 2'b00;
    assign S_AXI_RVALID  = axi_rvalid;

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_awready       <= 1'b0;
            axi_wready        <= 1'b0;
            axi_bvalid        <= 1'b0;

            reg_enable        <= 1'b1;
            reg_char_addr     <= 11'd0;
            reg_char_data     <= 8'h20;
            reg_fg_color      <= 12'h0F0;
            reg_bg_color      <= 12'h000;
            reg_canvas_wr_addr<= 10'd0;
            reg_canvas_wr_data<= 1'b0;
            reg_canvas_mode   <= 1'b0;

            clear_pulse       <= 1'b0;
            char_wr_pulse     <= 1'b0;
            canvas_wr_pulse   <= 1'b0;
        end
        else begin
            axi_awready     <= 1'b0;
            axi_wready      <= 1'b0;
            clear_pulse     <= 1'b0;
            char_wr_pulse   <= 1'b0;
            canvas_wr_pulse <= 1'b0;

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
                    ADDR_CHAR_ADDR: begin
                        if (S_AXI_WSTRB[0] || S_AXI_WSTRB[1])
                            reg_char_addr <= (S_AXI_WDATA[10:0] < 11'd1200) ? S_AXI_WDATA[10:0] : 11'd1199;
                    end
                    ADDR_CHAR_DATA: begin
                        if (S_AXI_WSTRB[0])
                            reg_char_data <= S_AXI_WDATA[7:0];
                    end
                    ADDR_WR_STRB: begin
                        if (S_AXI_WSTRB[0] && S_AXI_WDATA[0])
                            char_wr_pulse <= 1'b1;
                    end
                    ADDR_FG_COLOR: begin
                        if (S_AXI_WSTRB[0] || S_AXI_WSTRB[1])
                            reg_fg_color <= S_AXI_WDATA[11:0];
                    end
                    ADDR_BG_COLOR: begin
                        if (S_AXI_WSTRB[0] || S_AXI_WSTRB[1])
                            reg_bg_color <= S_AXI_WDATA[11:0];
                    end
                    ADDR_CANVAS_WR_ADDR: begin
                        if (S_AXI_WSTRB[0] || S_AXI_WSTRB[1])
                            reg_canvas_wr_addr <= (S_AXI_WDATA[9:0] < 10'd784) ? S_AXI_WDATA[9:0] : 10'd783;
                    end
                    ADDR_CANVAS_WR_DATA: begin
                        if (S_AXI_WSTRB[0])
                            reg_canvas_wr_data <= S_AXI_WDATA[0];
                    end
                    ADDR_CANVAS_WR_EN: begin
                        if (S_AXI_WSTRB[0] && S_AXI_WDATA[0])
                            canvas_wr_pulse <= 1'b1;
                    end
                    ADDR_CANVAS_MODE: begin
                        if (S_AXI_WSTRB[0])
                            reg_canvas_mode <= S_AXI_WDATA[0];
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
                    ADDR_CHAR_ADDR:      axi_rdata <= {21'd0, reg_char_addr};
                    ADDR_CHAR_DATA:      axi_rdata <= {24'd0, reg_char_data};
                    ADDR_WR_STRB:        axi_rdata <= 32'd0;
                    ADDR_FG_COLOR:       axi_rdata <= {20'd0, reg_fg_color};
                    ADDR_BG_COLOR:       axi_rdata <= {20'd0, reg_bg_color};
                    ADDR_CANVAS_WR_ADDR: axi_rdata <= {22'd0, reg_canvas_wr_addr};
                    ADDR_CANVAS_WR_DATA: axi_rdata <= {31'd0, reg_canvas_wr_data};
                    ADDR_CANVAS_WR_EN:   axi_rdata <= 32'd0;
                    ADDR_CANVAS_MODE:    axi_rdata <= {31'd0, reg_canvas_mode};
                    default:             axi_rdata <= 32'hDEAD_BEEF;
                endcase
            end
            else if (S_AXI_RREADY && axi_rvalid) begin
                axi_rvalid <= 1'b0;
            end
        end
    end

    vga_ctrl u_vga_ctrl(
        .clk(S_AXI_ACLK),
        .reset_p(!S_AXI_ARESETN),
        .enable(reg_enable),
        .clear(clear_pulse),
        .canvas_mode(reg_canvas_mode),
        .char_wr_addr(reg_char_addr),
        .char_wr_data(reg_char_data),
        .char_wr_en(char_wr_pulse),
        .canvas_wr_addr(reg_canvas_wr_addr),
        .canvas_wr_data(reg_canvas_wr_data),
        .canvas_wr_en(canvas_wr_pulse),
        .fg_color(reg_fg_color),
        .bg_color(reg_bg_color),
        .vgaRed(vgaRed),
        .vgaGreen(vgaGreen),
        .vgaBlue(vgaBlue),
        .Hsync(Hsync),
        .Vsync(Vsync),
        .clear_busy(clear_busy)
    );

endmodule
