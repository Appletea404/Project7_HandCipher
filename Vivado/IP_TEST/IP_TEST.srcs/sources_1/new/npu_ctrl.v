`timescale 1ns / 1ps

module npu_ctrl (
    input wire clk,
    input wire reset_p,
    input wire start,              // MicroBlaze AXI 제어기에서 주는 시작 펄스
    
    // 외장 28x28 캔버스 BRAM (Block Design의 BRAM Generator Port B에 직결)
    output reg [9:0] canvas_addrb, // 0 ~ 783 주소 버스
    output wire      canvas_enb,   // 읽기 활성화 (1'b1 고정)
    input wire       canvas_doutb, // BRAM에서 읽어온 1비트 픽셀 데이터
    
    // 제어 및 결과 레지스터 연결용
    output reg [4:0] result,       // Argmax 최종 결과 (0=A, 25=Z)
    output reg       busy,         // 연산 중 플래그 (STATUS[1])
    output reg       done          // 연산 완료 플래그 (STATUS[0])
);

    assign canvas_enb = 1'b1; // 항상 읽기 가능 상태 유지

    // --- FSM 상태 정의 ---
    localparam IDLE        = 3'b000;
    localparam LOAD_CANVAS = 3'b001; 
    localparam CALC_L1     = 3'b010; // 784 -> 64 레이어 연산
    localparam CALC_L2     = 3'b011; // 64 -> 26 레이어 연산
    localparam ARGMAX      = 3'b100; // 최고 점수 인덱스 추출
    localparam DONE        = 3'b101;

    reg [2:0] state;

    // --- 내부 연산용 레지스터 및 인덱스 카운터 ---
    reg [9:0] pixel_cnt;      // 0 ~ 783 카운터
    reg [5:0] hidden_cnt;     // 0 ~ 63 카운터
    reg [4:0] class_cnt;      // 0 ~ 25 카운터

    // 내부 버퍼: L1 연산 결과 저장 (uint8 노드 64개)
    reg [7:0] hidden_layer [0:63]; 
    
    // 누적 MAC 연산기, 최댓값 비교, 시프트 스케일링용 레지스터
    reg signed [31:0] l1_acc;      
    reg signed [31:0] l2_acc;      
    reg signed [31:0] max_score;
    reg signed [31:0] scaled_out;  // automatic 제거 후 상단 배치 완료
    
    // L2 스코어 임시 저장 어레이 (26개 출력 점수 보관용)
    reg signed [31:0] l2_score_buf [0:25];

    // BRAM 1클록 읽기 지연(Latency) 보정용 레지스터
    reg [9:0] canvas_addrb_reg;

    always @(posedge clk) begin
        canvas_addrb <= canvas_addrb_reg;
    end

    // --- 가중치/바이어스 ROM 주소 계산식선 정의 ---
    wire [15:0] w1_addr;
    wire [5:0]  b1_addr;
    wire [10:0] w2_addr;
    wire [4:0]  b2_addr;

    wire signed [7:0]  w1_data;
    wire signed [31:0] b1_data;
    wire signed [7:0]  w2_data;
    wire signed [31:0] b2_data;

    // 행렬 곱셈 주소 매핑 연속 할당
    assign w1_addr = (hidden_cnt * 784) + pixel_cnt;
    assign b1_addr = hidden_cnt;
    assign w2_addr = (class_cnt * 64) + hidden_cnt;
    assign b2_addr = class_cnt;

    // 1비트 입력을 uint8 정수(255 또는 0)로 복원하는 변수
    wire [7:0] pixel_uint8 = canvas_doutb ? 8'hFF : 8'h00;

    // --- FSM 제어 및 연산 로직 ---
    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            state <= IDLE;
            pixel_cnt <= 0;
            hidden_cnt <= 0;
            class_cnt <= 0;
            busy <= 1'b0;
            done <= 1'b0;
            result <= 0;
            l1_acc <= 0;
            l2_acc <= 0;
            max_score <= 32'sh80000000; // 가장 작은 음수로 초기화
            scaled_out <= 0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    busy <= 1'b0;
                    pixel_cnt <= 0;
                    hidden_cnt <= 0;
                    class_cnt <= 0;
                    l1_acc <= 0;
                    l2_acc <= 0;
                    max_score <= 32'sh80000000;
                    scaled_out <= 0;
                    if (start) begin
                        busy <= 1'b1;
                        canvas_addrb_reg <= 0;
                        state <= LOAD_CANVAS;
                    end
                end

                LOAD_CANVAS: begin
                    canvas_addrb_reg <= canvas_addrb_reg + 1;
                    state <= CALC_L1;
                end

                CALC_L1: begin
                    // L1 레이어 MAC (곱셈 누적 연산) 구동
                    l1_acc <= l1_acc + ($signed({1'b0, pixel_uint8}) * w1_data);

                    if (pixel_cnt < 783) begin
                        pixel_cnt <= pixel_cnt + 1;
                        canvas_addrb_reg <= pixel_cnt + 1;
                    end else begin
                        // 하나의 hidden 노드 누적이 완전히 끝난 시점 (784번 루프 완료)
                        // 바이어스를 더하고, SHIFT_L1(10) 만큼 시프트 스케일링 수행
                        scaled_out = (l1_acc + b1_data) >>> 10;

                        // ReLU 활성화 함수 및 Clamp(0, 255) 방어 코딩 적용
                        if (scaled_out < 0)
                            hidden_layer[hidden_cnt] <= 8'h00;
                        else if (scaled_out > 255)
                            hidden_layer[hidden_cnt] <= 8'hFF;
                        else
                            hidden_layer[hidden_cnt] <= scaled_out[7:0];

                        // 가산기 누적치 클리어
                        l1_acc <= 0;
                        pixel_cnt <= 0;
                        canvas_addrb_reg <= 0;

                        if (hidden_cnt < 63) begin
                            hidden_cnt <= hidden_cnt + 1;
                        end else begin
                            hidden_cnt <= 0;
                            state <= CALC_L2; // L1 연산 전체 완료 후 L2 진입
                        end
                    end
                end

                CALC_L2: begin
                    // L2 레이어 MAC: Hidden[64] * W2[64x26] 구동
                    l2_acc <= l2_acc + ($signed({1'b0, hidden_layer[hidden_cnt]}) * w2_data);

                    if (hidden_cnt < 63) begin
                        hidden_cnt <= hidden_cnt + 1;
                    end else begin
                        // 하나의 알파벳 클래스(출력 스코어) 연산이 끝난 시점 (64번 루프 완료)
                        // 바이어스 가산 후 결과 버퍼에 최종 저장 (L2는 시프트/ReLU 없음)
                        l2_score_buf[class_cnt] <= l2_acc + b2_data;
                        
                        l2_acc <= 0;
                        hidden_cnt <= 0;

                        if (class_cnt < 25) begin
                            class_cnt <= class_cnt + 1;
                        end else begin
                            class_cnt <= 0;
                            state <= ARGMAX; // 26개 알파벳 스코어 확보 완료
                        end
                    end
                end

                ARGMAX: begin
                    // 26개 점수 중 최댓값을 찾아내어 인덱스(0=A ~ 25=Z) 확정하기
                    if (l2_score_buf[class_cnt] > max_score) begin
                        max_score <= l2_score_buf[class_cnt];
                        result <= class_cnt;
                    end

                    if (class_cnt < 25) begin
                        class_cnt <= class_cnt + 1;
                    end else begin
                        state <= DONE;
                    end
                end

                DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

    // --- 하부 가중치/바이어스 ROM 모듈 4개 인스턴스화 하이웨이 ---
    weight_rom_l1 w1_rom_inst (.clk(clk), .addr(w1_addr), .data(w1_data));
    bias_rom_l1   b1_rom_inst (.clk(clk), .addr(b1_addr), .data(b1_data));
    weight_rom_l2 w2_rom_inst (.clk(clk), .addr(w2_addr), .data(w2_data));
    bias_rom_l2   b2_rom_inst (.clk(clk), .addr(b2_addr), .data(b2_data));

endmodule