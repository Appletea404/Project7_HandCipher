`timescale 1ns / 1ps

module tb_npu();

    // --- 시뮬레이션 클록 및 리셋 신호 ---
    reg clk;
    reg reset_p;
    
    // --- NPU 제어용 레지스터 신호 ---
    reg start;
    wire [4:0] result;
    wire busy;
    wire done;

    // --- 가상의 외장 캔버스 BRAM 배열 및 포트 ---
    wire [9:0] canvas_addrb;
    wire       canvas_enb;
    reg        canvas_doutb;
    
    // 784개의 픽셀을 보관할 테스트용 BRAM 가상 메모리
    reg virtual_bram [0:783];
    integer i;

    // --- 1. 테스트 인터페이스용 NPU AXI 래퍼 탑 인스턴스화 ---
    // 실제 Block Design 통합 환경과 똑같이 타이밍을 검증하기 위해 npu_axi를 불러옵니다.
    npu_axi uut (
        .canvas_addrb(canvas_addrb),
        .canvas_enb(canvas_enb),
        .canvas_doutb(canvas_doutb),

        // AXI 버스 타이밍용 신호 직결
        .S_AXI_ACLK(clk),
        .S_AXI_ARESETN(!reset_p), // 액티브 로우 반전
        .S_AXI_AWADDR(4'h0),       // 0x00 주소 (CTRL)
        .S_AXI_AWVALID(start),    // start 신호가 뜰 때 주소 유효
        .S_AXI_AWREADY(),
        .S_AXI_WDATA({31'h0, start}), // 데이터 하위 1비트에 start 주입
        .S_AXI_WSTRB(4'hF),
        .S_AXI_WVALID(start),     // start 신호가 뜰 때 데이터 유효
        .S_AXI_WREADY(),
        .S_AXI_BRESP(),
        .S_AXI_BVALID(),
        .S_AXI_BREADY(1'b1),      // 무조건 응답 수락
        
        // Read 채널 (시뮬레이션 가독성을 위해 미연결, 코어 포트로 직접 모니터링)
        .S_AXI_ARADDR(4'h0),
        .S_AXI_ARVALID(1'b0),
        .S_AXI_ARREADY(),
        .S_AXI_RDATA(),
        .S_AXI_RRESP(),
        .S_AXI_RVALID(),
        .S_AXI_RREADY(1'b0)
    );

    // --- 2. 100MHz 시스템 클록 생성 (10ns 주기) ---
    always #5 clk = ~clk;

    // --- 3. 외장 캔버스 BRAM 읽기 타이밍 시뮬레이션 (1클록 지연 재현) ---
    // Block Design의 BRAM Generator처럼 주소가 들어온 뒤 다음 클록에 데이터가 나오도록 설계합니다.
    always @(posedge clk) begin
        if (canvas_enb) begin
            canvas_doutb <= virtual_bram[canvas_addrb];
        end
    end

    // --- 4. 메인 시뮬레이션 시나리오 ---
    initial begin
        // 초기화
        clk = 1'b0;
        reset_p = 1'b1;
        start = 1'b0;
        
        // 가상 캔버스 BRAM 초기화 (임의로 지그재그 패턴 글자 주입)
        for(i = 0; i < 784; i = i + 1) begin
            if (i % 5 == 0) virtual_bram[i] = 1'b1; // 픽셀 그려짐
            else           virtual_bram[i] = 1'b0; // 빈 배경
        end

        // 리셋 해제 (100ns 뒤)
        #100;
        reset_p = 1'b0;
        #40;

        // [시나리오 1] MicroBlaze가 0x00(CTRL) 레지스터에 Start 트리거를 던짐
        $display("[TB] NPU 추론 시작 트리거 주입");
        start = 1'b1;
        #10; // 1클록 유지
        start = 1'b0;

        // [시나리오 2] NPU 가속기가 열심히 연산하는 동안 대기 (Busy 플래그 모니터링)
        // 약 150us ~ 160us 소요되므로 시뮬레이션 시간을 길게 관찰해야 합니다.
        wait(uut.npu_busy == 1'b1);
        $display("[TB] NPU 가속기 내부 연산 작동 중...");
        
        // [시나리오 3] 연산 완료 완료 신호(Done) 대기 및 결과 검증
        wait(uut.npu_done == 1'b1);
        $display("[TB] NPU 추론 완료! Done 신호 확인 완료.");
        $display("[TB] 최종 추론 출력 인덱스 (RESULT): %d (0=A, 1=B, ...)", uut.npu_result);

        // 시뮬레이션 종료
        #100;
        $display("[TB] 시뮬레이션 정상 종료");
        $finish;
    end

endmodule