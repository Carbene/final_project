module manual_selector_display (
    input  wire        clk,
    input  wire        rst_n,
    // 控制
    input  wire        start,            // 启动手动选择
    input  wire [2:0]  op_code,          // 操作码：0=转置，1=加法，2=标量乘，3=乘法

    // 与矩阵存储信息
    input  wire [49:0] info_table,       // 每个位置2bit计数，行优先打包

    // 与 matrix_selector_display 通信（第一个操作数选择）
    output reg         selector_op1_en,
    input  wire        selector_op1_done,
    input  wire        selector_op1_error,
    input  wire [2:0]  selector_op1_m,
    input  wire [2:0]  selector_op1_n,
    input  wire [199:0] selector_op1_matrix,

    // 与 matrix_selector_display 通信（第二个操作数选择，双目）
    output reg         selector_op2_en,
    input  wire        selector_op2_done,
    input  wire        selector_op2_error,
    input  wire [2:0]  selector_op2_m,
    input  wire [2:0]  selector_op2_n,
    input  wire [199:0] selector_op2_matrix,

    // 打印当前选择的矩阵
    output reg         print_start,
    output reg  [2:0]  print_dim_m,
    output reg  [2:0]  print_dim_n,
    output reg  [199:0] print_matrix,
    input  wire        print_done,

    // 发送给计算器（脉冲启动 ALU）
    output reg  [2:0]  m_a,
    output reg  [2:0]  n_a,
    output reg  [199:0] matrix_a_flat,
    output reg  [2:0]  m_b,
    output reg  [2:0]  n_b,
    output reg  [199:0] matrix_b_flat,
    output reg  [7:0]  scalar_out,       // 标量（0..9），仅数乘
    output reg         done,             // 脉冲：本次选择完成，ALU 启动计算
    output reg         error             // 脉冲：选择失败
);

    // 操作码常量
    localparam ALU_OP_TRANSPOSE = 3'd0;
    localparam ALU_OP_ADD       = 3'd1;
    localparam ALU_OP_SCALAR    = 3'd2;
    localparam ALU_OP_MUL       = 3'd3;

    // 状态机
    localparam S_IDLE          = 5'd0;
    localparam S_START         = 5'd1;
    localparam S_SEL_OP1       = 5'd2;   // 选择第一个操作数
    localparam S_SEL_OP1_WAIT  = 5'd3;   // 等待第一个选择完成
    localparam S_PRINT_OP1     = 5'd4;
    localparam S_PRINT_OP1_WAIT= 5'd5;
    localparam S_SEND_A        = 5'd6;
    localparam S_SEL_OP2       = 5'd7;   // 选择第二个操作数（双目）
    localparam S_SEL_OP2_WAIT  = 5'd8;   // 等待第二个选择完成
    localparam S_PRINT_OP2     = 5'd9;
    localparam S_PRINT_OP2_WAIT= 5'd10;
    localparam S_SEND_B        = 5'd11;
    localparam S_DONE          = 5'd12;
    localparam S_ERROR         = 5'd13;

    reg [4:0] state, next_state;
    reg [4:0] error_retry_state;  // 出错时返回的状态

    // LFSR 用于标量生成（仅数乘）
    reg [31:0] lfsr;
    wire [31:0] lfsr_next;
    assign lfsr_next[31:1] = lfsr[30:0];
    assign lfsr_next[0]    = lfsr[31] ^ lfsr[29] ^ lfsr[25] ^ lfsr[24];

    // 选择结果寄存
    reg [2:0] op1_m, op1_n, op2_m, op2_n;
    reg [199:0] op1_mat, op2_mat;

    // 维度合法性（1..5）
    function is_valid_dim;
        input [2:0] d;
        begin
            is_valid_dim = (d >= 3'd1) && (d <= 3'd5);
        end
    endfunction

    // 二目合法性检查
    function is_binary_match;
        input [2:0] opcode;
        input [2:0] m1, n1, m2, n2;
        begin
            case (opcode)
                ALU_OP_ADD:    is_binary_match = (m1 == m2) && (n1 == n2);
                ALU_OP_MUL:    is_binary_match = (n1 == m2);
                default:       is_binary_match = 1'b0;
            endcase
        end
    endfunction

    // 状态寄存 & LFSR更新
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            lfsr     <= 32'h13579BDF;
        end else begin
            state    <= next_state;
            lfsr     <= lfsr_next;
        end
    end

    // 次态逻辑
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE:          if (start) next_state = S_START;
            S_START:                          next_state = S_SEL_OP1;
            S_SEL_OP1:                        next_state = S_SEL_OP1_WAIT;
            S_SEL_OP1_WAIT: begin
                if (selector_op1_done && is_valid_dim(selector_op1_m) && is_valid_dim(selector_op1_n))
                    next_state = S_PRINT_OP1;
                else if (selector_op1_error)
                    // 出错，返回到该状态重新选择
                    next_state = S_SEL_OP1;
                else if (selector_op1_done)
                    // 维度无效，返回重新选择
                    next_state = S_SEL_OP1;
            end
            S_PRINT_OP1:                      next_state = S_PRINT_OP1_WAIT;
            S_PRINT_OP1_WAIT: if (print_done) next_state = S_SEND_A;
            S_SEND_A: begin
                case (op_code)
                    ALU_OP_TRANSPOSE, ALU_OP_SCALAR: next_state = S_DONE;
                    ALU_OP_ADD, ALU_OP_MUL:          next_state = S_SEL_OP2;
                    default:                         next_state = S_ERROR;
                endcase
            end
            S_SEL_OP2:                        next_state = S_SEL_OP2_WAIT;
            S_SEL_OP2_WAIT: begin
                if (selector_op2_done && is_valid_dim(selector_op2_m) && is_valid_dim(selector_op2_n) &&
                    is_binary_match(op_code, op1_m, op1_n, selector_op2_m, selector_op2_n))
                    next_state = S_PRINT_OP2;
                else if (selector_op2_error)
                    // 出错，返回重新选择
                    next_state = S_SEL_OP2;
                else if (selector_op2_done)
                    // 维度无效或不匹配，返回重新选择
                    next_state = S_SEL_OP2;
            end
            S_PRINT_OP2:                      next_state = S_PRINT_OP2_WAIT;
            S_PRINT_OP2_WAIT: if (print_done) next_state = S_SEND_B;
            S_SEND_B:                         next_state = S_DONE;
            S_DONE:                           next_state = S_IDLE;
            S_ERROR:                          next_state = S_IDLE;
            default:                          next_state = S_IDLE;
        endcase
    end

    // 时序输出与数据路径
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            selector_op1_en  <= 1'b0;
            selector_op2_en  <= 1'b0;
            print_start      <= 1'b0;
            print_dim_m      <= 3'd0;
            print_dim_n      <= 3'd0;
            print_matrix     <= 200'd0;
            m_a              <= 3'd0;
            n_a              <= 3'd0;
            matrix_a_flat    <= 200'd0;
            m_b              <= 3'd0;
            n_b              <= 3'd0;
            matrix_b_flat    <= 200'd0;
            scalar_out       <= 8'd0;
            done             <= 1'b0;
            error            <= 1'b0;
            op1_m            <= 3'd0;
            op1_n            <= 3'd0;
            op2_m            <= 3'd0;
            op2_n            <= 3'd0;
            op1_mat          <= 200'd0;
            op2_mat          <= 200'd0;
        end else begin
            // 默认清除脉冲
            selector_op1_en  <= 1'b0;
            selector_op2_en  <= 1'b0;
            print_start      <= 1'b0;
            done             <= 1'b0;
            error            <= 1'b0;

            case (state)
                S_IDLE: begin
                    // 空闲状态
                end
                S_START: begin
                    // 数乘生成 0..9 标量
                    if (op_code == ALU_OP_SCALAR)
                        scalar_out <= {4'd0, (lfsr[3:0] % 4'd10)};
                end
                S_SEL_OP1: begin
                    // 启动第一个操作数选择
                    selector_op1_en <= 1'b1;
                end
                S_SEL_OP1_WAIT: begin
                    // 等待选择完成
                    if (selector_op1_done) begin
                        op1_m <= selector_op1_m;
                        op1_n <= selector_op1_n;
                        op1_mat <= selector_op1_matrix;
                    end
                end
                S_PRINT_OP1: begin
                    // 打印第一个选择
                    print_start  <= 1'b1;
                    print_dim_m  <= op1_m;
                    print_dim_n  <= op1_n;
                    print_matrix <= op1_mat;
                end
                S_SEND_A: begin
                    // 发送A给计算器
                    m_a           <= op1_m;
                    n_a           <= op1_n;
                    matrix_a_flat <= op1_mat;
                end
                S_SEL_OP2: begin
                    // 启动第二个操作数选择
                    selector_op2_en <= 1'b1;
                end
                S_SEL_OP2_WAIT: begin
                    // 等待选择完成
                    if (selector_op2_done) begin
                        op2_m <= selector_op2_m;
                        op2_n <= selector_op2_n;
                        op2_mat <= selector_op2_matrix;
                    end
                end
                S_PRINT_OP2: begin
                    // 打印第二个选择
                    print_start  <= 1'b1;
                    print_dim_m  <= op2_m;
                    print_dim_n  <= op2_n;
                    print_matrix <= op2_mat;
                end
                S_SEND_B: begin
                    // 发送B给计算器
                    m_b           <= op2_m;
                    n_b           <= op2_n;
                    matrix_b_flat <= op2_mat;
                end
                S_DONE: begin
                    // 脉冲启动 ALU 计算
                    done <= 1'b1;
                end
                S_ERROR: begin
                    error <= 1'b1;
                end
            endcase
        end
    end

endmodule
