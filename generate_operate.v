//==============================================================================
// 模块名称：generate_mode
// 功能：通过 LFSR 生成指定数量 (num) 的 M*N 随机矩阵
// 优化：修复了 1*1 矩阵下的双重计数死循环问题
// 结构：3-staged FSM
//==============================================================================

module generate_mode #(
    parameter [7:0] elem_min = 8'd0,
    parameter [7:0] elem_max = 8'd9
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [7:0]   uart_data,
    input  wire         uart_data_valid,
    output reg [199:0]  gen_matrix_flat,
    output reg          gen_done,
    output reg          gen_valid, // 每生成完一个矩阵拉高1拍
    output reg [2:0]    gen_m,
    output reg [2:0]    gen_n,
    output reg          error
);

    // 状态定义
    localparam IDLE         = 3'd0;
    localparam RECEIVE_M    = 3'd1;
    localparam RECEIVE_N    = 3'd2;
    localparam RECEIVE_NUM  = 3'd3;
    localparam GENERATE     = 3'd4;
    localparam WAIT_WRITE   = 3'd5; // 关键：用于同步和拉低 valid
    localparam DONE         = 3'd6;
    localparam ERR          = 3'd7;

    reg [2:0] state, next_state;
    
    // 内部寄存器
    reg [1:0] num_to_gen;
    reg [1:0] gen_cnt;
    reg [2:0] i, j;
    reg [15:0] lfsr;
    
    // 辅助组合逻辑
    wire [7:0] dealed_data = (uart_data >= 8'h30 && uart_data <= 8'h39) ? (uart_data - 8'h30) : 8'd0;
    wire last_element = (i == gen_m - 1) && (j == gen_n - 1);
    wire matrix_done  = (state == GENERATE) && last_element;
    
    // 随机数处理逻辑 (使用组合逻辑预计算)
    reg [7:0] next_v;
    always @(*) begin
        next_v = {4'd0, lfsr[3:0]};
        if (next_v > elem_max) next_v = next_v - (elem_max - elem_min + 1);
        if (next_v < elem_min) next_v = elem_min;
        if (next_v > 8'd9)     next_v = 8'd9;
    end

    //-------------------------------------------------------
    // 第一段：状态寄存器 (Sequential)
    //-------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            state <= IDLE;
        else 
            state <= next_state;
    end

    //-------------------------------------------------------
    // 第二段：状态转移逻辑 (Combinational)
    //-------------------------------------------------------
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (start) next_state = RECEIVE_M;
            end
            RECEIVE_M: begin
                if (uart_data_valid) next_state = RECEIVE_N;
            end
            RECEIVE_N: begin
                if (uart_data_valid) next_state = RECEIVE_NUM;
            end
            RECEIVE_NUM: begin
                if (uart_data_valid) next_state = GENERATE;
            end
            GENERATE: begin
                if (gen_m == 0 || gen_n == 0) 
                    next_state = ERR;
                else if (matrix_done) // 组合逻辑判断，立即跳转，不留空档
                    next_state = WAIT_WRITE;
            end
            WAIT_WRITE: begin
                if (gen_cnt >= num_to_gen) 
                    next_state = DONE;
                else 
                    next_state = GENERATE;
            end
            DONE: begin
                if (!start) next_state = IDLE;
            end
            ERR: begin
                if(!start)
                next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

    //-------------------------------------------------------
    // 第三段：输出逻辑与数据通路 (Sequential)
    //-------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gen_m <= 3'd0; gen_n <= 3'd0;
            num_to_gen <= 2'd0; gen_cnt <= 2'd0;
            i <= 3'd0; j <= 3'd0;
            lfsr <= 16'hACE1; // 非零种子
            gen_matrix_flat <= 200'd0;
            gen_done <= 1'b0; gen_valid <= 1'b0;
            error <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    gen_done <= 1'b0; gen_valid <= 1'b0; error <= 1'b0;
                    gen_cnt <= 2'd0; i <= 3'd0; j <= 3'd0;
                    gen_matrix_flat <= 200'd0;
                end

                RECEIVE_M: if (uart_data_valid) gen_m <= dealed_data[2:0];
                RECEIVE_N: if (uart_data_valid) gen_n <= dealed_data[2:0];
                RECEIVE_NUM: if (uart_data_valid) num_to_gen <= (dealed_data > 2) ? 2'd2 : dealed_data[1:0];

                GENERATE: begin
                    gen_valid <= 1'b0; // 默认拉低
                    // 填入当前随机值
                    gen_matrix_flat[(i * gen_n + j) * 8 +: 8] <= next_v;
                    // 更新 LFSR
                    lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
                    
                    // 坐标更新逻辑
                    if (j == gen_n - 1) begin
                        j <= 3'd0;
                        if (i == gen_m - 1) begin
                            i <= 3'd0;
                            gen_cnt <= gen_cnt + 1'b1;
                            gen_valid <= 1'b1; // 矩阵完成，拉高一个时钟周期
                        end else begin
                            i <= i + 1'b1;
                        end
                    end else begin
                        j <= j + 1'b1;
                    end
                end

                WAIT_WRITE: begin
                    gen_valid <= 1'b0; // 确保只保持一拍
                end

                DONE: begin 
                    gen_done <= 1'b1;
                end

                ERR: error <= 1'b1;
            endcase
        end
    end

endmodule