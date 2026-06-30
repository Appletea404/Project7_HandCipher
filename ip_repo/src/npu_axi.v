`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////


`timescale 1ns / 1ps

module npu_axi # (
    // AXI4-Lite 슬레이브 파라미터 (주소 및 데이터 폭)
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 4       // 3개 레지스터 제어용 (4비트면 충분)
)(
    // --- 외장 캔버스 BRAM Port B 직결 핀 (Block Design 연결용) ---
    output wire [9:0] canvas_addrb,
    output wire      canvas_enb,
    input wire       canvas_doutb,

    // --- 표준 AXI4-Lite 슬레이브 인터페이스 핀 ---
    input wire  S_AXI_ACLK,
    input wire  S_AXI_ARESETN,
    input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_AWADDR,
    input wire  S_AXI_AWVALID,
    output wire S_AXI_AWREADY,
    input wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_WDATA,
    input wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_WSTRB, // 미사용 보존
    input wire  S_AXI_WVALID,
    output wire S_AXI_WREADY,
    output wire [1 : 0] S_AXI_BRESP,
    output wire S_AXI_BVALID,
    input wire  S_AXI_BREADY,
    input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_ARADDR,
    input wire  S_AXI_ARVALID,
    output wire S_AXI_ARREADY,
    output wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_RDATA,
    output wire [1 : 0] S_AXI_RRESP,
    output wire  S_AXI_RVALID,
    input wire  S_AXI_RREADY
);

    // --- 내부 레지스터 선언 ---
    reg [C_S_AXI_DATA_WIDTH-1 : 0] reg_ctrl;    // 0x00
    reg                            axi_awready;
    reg                            axi_wready;
    reg                            axi_bvalid;
    reg                            axi_arready;
    reg [C_S_AXI_DATA_WIDTH-1 : 0] axi_rdata;
    reg                            axi_rvalid;

    // --- NPU 코어 내부 연결용 신호선 ---
    reg  npu_start;
    wire npu_busy;
    wire npu_done;
    wire [4:0] npu_result;

    // --- AXI 응답 고정값 ---
    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY  = axi_wready;
    assign S_AXI_BRESP   = 2'b00; // OKAY
    assign S_AXI_BVALID  = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RDATA   = axi_rdata;
    assign S_AXI_RRESP   = 2'b00; // OKAY
    assign S_AXI_RVALID  = axi_rvalid;

    // --- 1. AXI Write (MicroBlaze -> NPU 제어명령) ---
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_awready <= 1'b0;
            axi_wready  <= 1'b0;
            axi_bvalid  <= 1'b0;
            reg_ctrl    <= 32'h0;
            npu_start   <= 1'b0;
        end else begin
            // 펄스성 start 신호 처리를 위해 매 클록마다 클리어 준비
            npu_start <= 1'b0;

            // 주소 및 데이터가 유효할 때 한 번에 Write 수락
            if (S_AXI_AWVALID && S_AXI_WVALID && !axi_awready) begin
                axi_awready <= 1'b1;
                axi_wready  <= 1'b1;
                axi_bvalid  <= 1'b1;

                // 0x00 주소(CTRL)에 데이터가 들어왔을 때 처리
                if (S_AXI_AWADDR[3:2] == 2'b00) begin
                    reg_ctrl <= S_AXI_WDATA;
                    if (S_AXI_WDATA[0] == 1'b1) begin
                        npu_start <= 1'b1; // NPU 구동 트리거 활성화
                    end
                end
            end else begin
                if (S_AXI_BREADY && axi_bvalid) begin
                    axi_bvalid <= 1'b0;
                end
                axi_awready <= 1'b0;
                axi_wready  <= 1'b0;
            end
        end
    end

    // --- 2. AXI Read (MicroBlaze가 NPU 상태/결과 읽기) ---
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_arready <= 1'b0;
            axi_rdata   <= 32'h0;
            axi_rvalid  <= 1'b0;
        end else begin
            if (S_AXI_ARVALID && !axi_arready) begin
                axi_arready <= 1'b1;
                axi_rvalid  <= 1'b1;

                case (S_AXI_ARADDR[3:2])
                    2'b00: axi_rdata <= reg_ctrl; // 0x00: CTRL 읽기 (디버그용)
                    2'b01: axi_rdata <= {30'h0, npu_busy, npu_done}; // 0x04: STATUS 플래그 매핑
                    2'b10: axi_rdata <= {27'h0, npu_result};         // 0x08: RESULT 최종 레이블
                    default: axi_rdata <= 32'hDEADBEEF;
                endcase
            end else begin
                if (S_AXI_RREADY && axi_rvalid) begin
                    axi_rvalid <= 1'b0;
                end
                axi_arready <= 1'b0;
            end
        end
    end

    // --- 3. 앞서 우리가 완성한 NPU 연산 가속기 하부 실체 인스턴스화 ---
    npu_ctrl npu_core_inst (
        .clk(S_AXI_ACLK),
        .reset_p(!S_AXI_ARESETN), // AXI의 액티브 로우 리셋을 액티브 하이로 반전 연결
        .start(npu_start),
        
        // 외장 BRAM 인터페이스 상부 바이패스 패스스루
        .canvas_addrb(canvas_addrb),
        .canvas_enb(canvas_enb),
        .canvas_doutb(canvas_doutb),
        
        // 레지스터 매핑선 연결
        .result(npu_result),
        .busy(npu_busy),
        .done(npu_done)
    );

endmodule