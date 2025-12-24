module generate_mode#(
    parameter elem_min = 8'd0,
    parameter elem_max = 8'd9
)(
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [7:0] uart_data,
    input wire uart_data_valid,
    output reg [199:0] gen_matrix_flat,
    output reg gen_done,
    output reg gen_valid, // 新增：每生成一个矩阵拉高1拍
    output reg[2:0] gen_m,
    output reg[2:0] gen_n,
    output reg error
);
    // 状态机定义
    localparam IDLE=3'd0;
    localparam RECEIVE_M=3'd1;
    localparam RECEIVE_N=3'd2;
    localparam RECEIVE_NUM=3'd3;
    localparam GENERATE=3'd4;
    localparam WAIT_WRITE=3'd5;
    localparam DONE=3'd6;
    localparam ERR=3'd7;
    reg [2:0] state, next_state;
    reg [1:0] num; // 生成矩阵数量
    reg [1:0] gen_cnt; // 已生成计数
    reg [2:0] i, j;
    reg [15:0] lfsr;
    reg [7:0] v;
    reg busy;
    wire [7:0] dealed_data = uart_data - 8'h30; // ASCII '0'=0x30=48，转数值

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state <= IDLE;
            gen_m <= 3'd0;
            gen_n <= 3'd0;
            num <= 2'd0;
            gen_cnt <= 2'd0;
            i <= 3'd0;
            j <= 3'd0;
            lfsr <= 16'hACE1;
            gen_matrix_flat <= 200'd0;
            gen_done <= 1'b0;
            gen_valid <= 1'b0;
            error <= 1'b0;
            busy <= 1'b0;
        end else begin
            state <= next_state;
            case(state)
                IDLE: begin
                    gen_done <= 1'b0;
                    gen_valid <= 1'b0;
                    error <= 1'b0;
                    busy <= 1'b0;
                    gen_cnt <= 2'd0;
                end
                RECEIVE_M: if(uart_data_valid) begin
                    if(dealed_data[2:0] == 3'd0 || dealed_data[2:0] > 3'd5)
                        gen_m <= 3'd0;  // 无效值，会触发错误
                    else
                        gen_m <= dealed_data[2:0];
                end
                RECEIVE_N: if(uart_data_valid) begin
                    if(dealed_data[2:0] == 3'd0 || dealed_data[2:0] > 3'd5)
                        gen_n <= 3'd0;  // 无效值，会触发错误
                    else
                        gen_n <= dealed_data[2:0];
                end
                RECEIVE_NUM: if(uart_data_valid) num <= (dealed_data > 2) ? 2 : dealed_data[1:0];
                GENERATE: begin
                    busy <= 1'b1;
                    gen_valid <= 1'b0;
                    // 检查矩阵尺寸是否有效
                    if (gen_m == 3'd0 || gen_n == 3'd0) begin
                        // 尺寸无效，跳转到错误状态
                        error <= 1'b1;
                    end else if (i < gen_m && j < gen_n) begin
                        v = {4'd0, lfsr[3:0]};
                        if (v > elem_max) v = v - (elem_max - elem_min + 1);
                        if (v < elem_min) v = elem_min;
                        if (v > 8'd9)    v = 8'd9;
                        gen_matrix_flat[(i*gen_n+j)*8 +: 8] <= v;
                        lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
                        if (j == gen_n - 1) begin
                            j <= 0;
                            if (i == gen_m - 1) begin
                                i <= 0;
                                gen_cnt <= gen_cnt + 1'b1;
                                gen_valid <= 1'b1; // 生成完一个矩阵，拉高valid
                            end else begin
                                i <= i + 1'b1;
                            end
                        end else begin
                            j <= j + 1'b1;
                        end
                    end
                end
                WAIT_WRITE: begin
                    gen_valid <= 1'b0; // valid只拉高1拍
                end
                DONE: begin
                    gen_done <= 1'b1;
                    busy <= 1'b0;
                    gen_valid <= 1'b0;
                end
                ERR: error <= 1'b1;
                default: ;
            endcase
        end
    end

    always @(*) begin
        next_state = state;
        case(state)
            IDLE: if(start) next_state = RECEIVE_M;
            RECEIVE_M: if(uart_data_valid) next_state = RECEIVE_N;
            RECEIVE_N: if(uart_data_valid) next_state = RECEIVE_NUM;
            RECEIVE_NUM: if(uart_data_valid) next_state = GENERATE;
            GENERATE: begin
                if (gen_m == 3'd0 || gen_n == 3'd0)
                    next_state = ERR;
                else if(gen_valid)
                    next_state =  WAIT_WRITE;
            end
            WAIT_WRITE: if(gen_cnt==num) next_state = DONE;
                        else next_state = GENERATE;
            DONE: next_state = IDLE;
            ERR: next_state = RECEIVE_M;
            default: next_state = IDLE;
        endcase
    end
endmodule