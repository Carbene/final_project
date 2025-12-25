module random_selector_display (
    input  wire        clk,
    input  wire        rst_n,
    // 控制
    input  wire        start,            // 启动随机选择
    input  wire [2:0]  op_code,          // 操作码：0=转置，1=加法，2=标量乘，3=乘法

    // 矩阵存储信息与读取接口
    input  wire [49:0] info_table,       // 每个位置2bit计数，行优先打包
    output reg         read_en,
    output reg  [2:0]  rd_row,           // 行=m
    output reg  [2:0]  rd_col,           // 列=n
    output reg  [1:0]  rd_mat_index,     // 槽位索引 0/1
    input  wire        rd_ready,
    input  wire [199:0] rd_data_flow,

    // 打印当前选择的矩阵
    output reg         print_start,
    output reg  [2:0]  print_dim_m,
    output reg  [2:0]  print_dim_n,
    output reg  [199:0] print_matrix,
    input  wire        print_done,

    // 发送给计算器（逐个发送）
    output reg  [2:0]  m_a,
    output reg  [2:0]  n_a,
    output reg  [199:0] matrix_a_flat,

    output reg  [2:0]  m_b,
    output reg  [2:0]  n_b,
    output reg  [199:0] matrix_b_flat,

    output reg  [7:0]  scalar_out,       // 标量（0..9），仅数乘
    
    output reg         done,             // 本次选择流程完成
    output reg         error             // 选择失败
);

    // 操作码常量
    localparam ALU_OP_TRANSPOSE = 3'd0;
    localparam ALU_OP_ADD       = 3'd1;
    localparam ALU_OP_SCALAR    = 3'd2;
    localparam ALU_OP_MUL       = 3'd3;

    // 状态机
    localparam S_IDLE          = 5'd0;
    localparam S_START         = 5'd1;
    localparam S_GEN_OP1       = 5'd2;
    localparam S_CHECK_OP1     = 5'd3;
    localparam S_READ_OP1_REQ  = 5'd4;
    localparam S_READ_OP1_WAIT = 5'd5;
    localparam S_PRINT_OP1     = 5'd6;
    localparam S_PRINT_OP1_WAIT= 5'd7;
    localparam S_SEND_A        = 5'd8;
    localparam S_GEN_OP2       = 5'd9;
    localparam S_CHECK_OP2     = 5'd10;
    localparam S_READ_OP2_REQ  = 5'd11;
    localparam S_READ_OP2_WAIT = 5'd12;
    localparam S_PRINT_OP2     = 5'd13;
    localparam S_PRINT_OP2_WAIT= 5'd14;
    localparam S_SEND_B        = 5'd15;
    localparam S_DONE          = 5'd16;
    localparam S_ERROR         = 5'd17;

    reg [4:0] state, next_state;

    // LFSR 随机源（32位）
    reg [31:0] lfsr;
    wire [31:0] lfsr_next;
    assign lfsr_next[31:1] = lfsr[30:0];
    assign lfsr_next[0]    = lfsr[31] ^ lfsr[29] ^ lfsr[25] ^ lfsr[24];

    // 随机位置 0..24（行优先）
    wire [4:0] rand_pos = lfsr[4:0] % 5'd25;

    // 已尝试标记与重试计数
    reg [24:0] tried;      // 标记每个位置是否尝试过
    reg [7:0]  retry_cnt;
    localparam MAX_RETRY = 8'd100;

    // 选择结果寄存
    reg [4:0] op1_pos, op2_pos;
    reg [2:0] op1_m, op1_n, op2_m, op2_n;
    reg [199:0] op1_mat, op2_mat;
    reg [1:0] op1_id, op2_id;

    // info_table 提取计数（行优先打包，低位在前）
    wire [1:0] cnt_op1 = info_table[(op1_pos << 1) +: 2];
    wire [1:0] cnt_op2 = info_table[(op2_pos << 1) +: 2];

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
            S_START:                          next_state = S_GEN_OP1;
            S_GEN_OP1:                        next_state = S_CHECK_OP1;
            S_CHECK_OP1: begin
                if (cnt_op1 != 2'd0 && is_valid_dim(op1_m) && is_valid_dim(op1_n))
                    next_state = S_READ_OP1_REQ;
                else if (retry_cnt < MAX_RETRY)
                    next_state = S_GEN_OP1;
                else
                    next_state = S_ERROR;
            end
            S_READ_OP1_REQ:                  next_state = S_READ_OP1_WAIT;
            S_READ_OP1_WAIT:  if (rd_ready) next_state = S_PRINT_OP1;
            S_PRINT_OP1:                      next_state = S_PRINT_OP1_WAIT;
            S_PRINT_OP1_WAIT: if (print_done) next_state = S_SEND_A;
            S_SEND_A: begin
                case (op_code)
                    ALU_OP_TRANSPOSE, ALU_OP_SCALAR: next_state = S_DONE;
                    ALU_OP_ADD, ALU_OP_MUL:          next_state = S_GEN_OP2;
                    default:                         next_state = S_ERROR;
                endcase
            end
            S_GEN_OP2:                        next_state = S_CHECK_OP2;
            S_CHECK_OP2: begin
                if (cnt_op2 != 2'd0 && is_valid_dim(op2_m) && is_valid_dim(op2_n) &&
                    is_binary_match(op_code, op1_m, op1_n, op2_m, op2_n))
                    next_state = S_READ_OP2_REQ;
                else if (retry_cnt < MAX_RETRY)
                    next_state = S_GEN_OP2;
                else
                    next_state = S_ERROR;
            end
            S_READ_OP2_REQ:                  next_state = S_READ_OP2_WAIT;
            S_READ_OP2_WAIT:  if (rd_ready) next_state = S_PRINT_OP2;
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
            read_en         <= 1'b0;
            rd_row          <= 3'd0;
            rd_col          <= 3'd0;
            rd_mat_index    <= 2'd0;
            print_start     <= 1'b0;
            print_dim_m     <= 3'd0;
            print_dim_n     <= 3'd0;
            print_matrix    <= 200'd0;
            send_a          <= 1'b0;
            send_b          <= 1'b0;
            m_a             <= 3'd0;
            n_a             <= 3'd0;
            matrix_a_flat   <= 200'd0;
            m_b             <= 3'd0;
            n_b             <= 3'd0;
            matrix_b_flat   <= 200'd0;
            scalar_out      <= 8'd0;
            done            <= 1'b0;
            error           <= 1'b0;
            tried           <= 25'd0;
            retry_cnt       <= 8'd0;
            op1_pos         <= 5'd0;
            op2_pos         <= 5'd0;
            op1_m           <= 3'd0;
            op1_n           <= 3'd0;
            op2_m           <= 3'd0;
            op2_n           <= 3'd0;
            op1_mat         <= 200'd0;
            op2_mat         <= 200'd0;
            op1_id          <= 2'd0;
            op2_id          <= 2'd0;
        end else begin
            // 默认清除脉冲
            read_en     <= 1'b0;
            print_start <= 1'b0;
            send_a      <= 1'b0;
            send_b      <= 1'b0;
            done        <= 1'b0;
            error       <= 1'b0;

            case (state)
                S_IDLE: begin
                    tried     <= 25'd0;
                    retry_cnt <= 8'd0;
                end
                S_START: begin
                    // 数乘生成 0..9 标量（低4位+1位混合并模10）
                    if (op_code == ALU_OP_SCALAR)
                        scalar_out <= {4'd0, (lfsr[3:0] % 4'd10)};
                end
                S_GEN_OP1: begin
                    op1_pos            <= rand_pos;
                    tried[rand_pos]    <= 1'b1;
                    retry_cnt          <= retry_cnt + 1'b1;
                    op1_m              <= (rand_pos / 5'd5) + 3'd1; // 行：1..5
                    op1_n              <= (rand_pos % 5'd5) + 3'd1; // 列：1..5
                    // 槽位选择：若计数为2则交替，若为1优先0槽
                    op1_id             <= (cnt_op1 == 2'd2) ? lfsr[1:0] & 2'd1 : 2'd0;
                end
                S_READ_OP1_REQ: begin
                    read_en     <= 1'b1;           // 单拍读取
                    rd_row      <= op1_m;          // 行优先映射：rd_row=m
                    rd_col      <= op1_n;          // 列：rd_col=n
                    rd_mat_index<= op1_id;
                end
                S_READ_OP1_WAIT: begin
                    if (rd_ready) begin
                        op1_mat <= rd_data_flow;
                    end
                end
                S_PRINT_OP1: begin
                    print_start  <= 1'b1;          // 启动打印当前选择
                    print_dim_m  <= op1_m;
                    print_dim_n  <= op1_n;
                    print_matrix <= op1_mat;
                end
                S_SEND_A: begin
                    // 发送A给计算器
                    send_a        <= 1'b1;
                    m_a           <= op1_m;
                    n_a           <= op1_n;
                    matrix_a_flat <= op1_mat;
                end
                S_GEN_OP2: begin
                    op2_pos            <= rand_pos;
                    tried[rand_pos]    <= 1'b1;
                    retry_cnt          <= retry_cnt + 1'b1;
                    op2_m              <= (rand_pos / 5'd5) + 3'd1;
                    op2_n              <= (rand_pos % 5'd5) + 3'd1;
                    op2_id             <= (cnt_op2 == 2'd2) ? lfsr[3:2] & 2'd1 : 2'd0;
                end
                S_READ_OP2_REQ: begin
                    read_en     <= 1'b1;
                    rd_row      <= op2_m;
                    rd_col      <= op2_n;
                    rd_mat_index<= op2_id;
                end
                S_READ_OP2_WAIT: begin
                    if (rd_ready) begin
                        op2_mat <= rd_data_flow;
                    end
                end
                S_PRINT_OP2: begin
                    print_start  <= 1'b1;
                    print_dim_m  <= op2_m;
                    print_dim_n  <= op2_n;
                    print_matrix <= op2_mat;
                end
                S_SEND_B: begin
                    send_b        <= 1'b1;
                    m_b           <= op2_m;
                    n_b           <= op2_n;
                    matrix_b_flat <= op2_mat;
                end
                S_DONE: begin
                    done <= 1'b1;
                end
                S_ERROR: begin
                    error <= 1'b1;
                end
            endcase
        end
    end

endmodule
