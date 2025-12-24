module random_selector (
    // 时钟与复位
    input  clk,
    input  rst_n,
    
    // 控制信号
    input  enable,              // 启用随机选择
    input  [2:0] op_code,       // 操作码：0=转置，1=加法，2=标量乘法，3=乘法
    
    // 与矩阵存储通信
    input  [49:0] info_table,   // 矩阵信息表（每个位置2 bit计数）
    output reg [1:0] query_index,  // 查询矩阵索引（0或1）
    output reg [2:0] query_dim_m,  // 查询维度 m
    output reg [2:0] query_dim_n,  // 查询维度 n
    
    // 与矩阵存储的读接口
    output reg read_en,
    output reg [2:0] rd_col,
    output reg [2:0] rd_row,
    output reg [1:0] rd_mat_index,
    input  [199:0] rd_data_flow,
    input  rd_ready,
    
    // 与计算模块通信
    output reg [2:0] sel_dim_m,
    output reg [2:0] sel_dim_n,
    output reg [199:0] sel_matrix,
    output reg [1:0] sel_matrix_id,  // 选中矩阵的 ID（0 或 1）
    output reg sel_done,
    output reg sel_error,
    
    // 与矩阵打印模块通信
    output reg print_start,
    output reg [2:0] print_dim_m,
    output reg [2:0] print_dim_n,
    output reg [199:0] print_matrix,
    input  print_done
);

    //================== 操作码定义 ==================
    localparam OP_TRANSPOSE = 3'd0;
    localparam OP_ADD       = 3'd1;
    localparam OP_SCALAR    = 3'd2;
    localparam OP_MUL       = 3'd3;

    //================== 状态定义 ==================
    localparam IDLE                 = 5'd0;
    localparam GEN_RAND_OP1         = 5'd1;   // 生成第一个操作数的随机位置
    localparam QUERY_OP1            = 5'd2;   // 查询第一个位置是否有元素
    localparam CHECK_OP1_EXISTS     = 5'd3;   // 检查第一个操作数是否存在
    localparam READ_OP1             = 5'd4;   // 读取第一个操作数
    localparam PRINT_OP1            = 5'd5;   // 打印第一个操作数
    localparam PRINT_OP1_WAIT       = 5'd6;   // 等待打印完成
    localparam GEN_RAND_OP2         = 5'd7;   // 生成第二个操作数的随机位置（双目）
    localparam QUERY_OP2            = 5'd8;   // 查询第二个位置是否有元素
    localparam CHECK_OP2_VALID      = 5'd9;   // 检查第二个操作数是否合法
    localparam READ_OP2             = 5'd10;  // 读取第二个操作数
    localparam PRINT_OP2            = 5'd11;  // 打印第二个操作数
    localparam PRINT_OP2_WAIT       = 5'd12;  // 等待打印完成
    localparam DONE                 = 5'd13;  // 选择完成
    localparam ERROR                = 5'd14;  // 错误状态

    //================== 维度限制 ==================
    localparam MIN_DIM = 3'd1;
    localparam MAX_DIM = 3'd5;

    //================== 状态寄存器 ==================
    reg [4:0] state, next_state;
    
    //================== LFSR 随机数生成器 ==================
    reg [31:0] lfsr;                // 32 bit LFSR
    wire [31:0] lfsr_next;          // 下一个 LFSR 值
    wire [4:0] rand_pos;            // 随机位置（0-24）
    
    // LFSR 反馈多项式：x^32 + x^30 + x^26 + x^25 + 1（Gallois配置）
    assign lfsr_next[31:1] = lfsr[30:0];
    assign lfsr_next[0] = lfsr[31] ^ lfsr[29] ^ lfsr[25] ^ lfsr[24];
    
    // 生成 0-24 的随机数
    assign rand_pos = lfsr[4:0] % 5'd25;  // 模 25 得到矩阵位置

    //================== 位置转换函数 ==================
    // 从线性位置（0-24）转换为矩阵坐标（m, n）
    function [5:0] pos_to_coord;
        input [4:0] pos;
        begin
            pos_to_coord = {pos / 5'd5, pos % 5'd5};  // {m, n}
        end
    endfunction

    //================== 维度检查函数 ==================
    function is_valid_dim;
        input [2:0] dim;
        begin
            is_valid_dim = (dim >= MIN_DIM) && (dim <= MAX_DIM);
        end
    endfunction

    //================== 查询矩阵位置是否有元素（内联函数代替） ==================
    // 通过组合逻辑实现，不使用 function

    //================== 检查双目运算符合法性 ==================
    // 对于加法：两个矩阵维度相同
    // 对于乘法：第一个矩阵的列数 == 第二个矩阵的行数
    function check_binary_valid;
        input [2:0] op;
        input [2:0] m1, n1, m2, n2;
        begin
            case (op)
                OP_ADD: check_binary_valid = (m1 == m2) && (n1 == n2);
                OP_MUL: check_binary_valid = (n1 == m2);
                default: check_binary_valid = 1'b0;
            endcase
        end
    endfunction

    //================== 数据寄存器 ==================
    reg [4:0] op1_pos, op2_pos;           // 随机选择的操作数位置
    reg [2:0] op1_m, op1_n, op2_m, op2_n; // 操作数维度
    reg [199:0] op1_matrix, op2_matrix;   // 操作数矩阵数据
    reg [1:0] op1_id, op2_id;             // 操作数来自哪个槽位（0或1）
    reg [24:0] tried_positions;           // 25 bit 数组，记录已尝试的位置
    reg [7:0] retry_count;                // 重试计数（防止死循环）
    
    localparam MAX_RETRY = 8'd50;         // 最多尝试 50 次
    
    // 内联逻辑：提取矩阵计数
    wire [1:0] op1_count = info_table[(op1_pos << 1) +: 2];
    wire [1:0] op2_count = info_table[(op2_pos << 1) +: 2];

    //================== 第一段：状态寄存 ==================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            lfsr <= 32'h12345678;  // 初始 LFSR 种子
        end else begin
            state <= next_state;
            lfsr <= lfsr_next;     // 每个时钟周期更新 LFSR
        end
    end

    //================== 第二段：次态逻辑 ==================
    always @(*) begin
        next_state = state;
        
        case (state)
            IDLE: begin
                if (enable)
                    next_state = GEN_RAND_OP1;
            end

            GEN_RAND_OP1:
                next_state = QUERY_OP1;

            QUERY_OP1:
                next_state = CHECK_OP1_EXISTS;

            CHECK_OP1_EXISTS: begin
                // 如果该位置有元素，进行读取
                if (op1_count != 2'd0)
                    next_state = READ_OP1;
                // 否则重新生成随机位置
                else if (retry_count < MAX_RETRY)
                    next_state = GEN_RAND_OP1;
                else
                    next_state = ERROR;
            end

            READ_OP1:
                next_state = PRINT_OP1;

            PRINT_OP1: begin
                if (!print_done)
                    next_state = PRINT_OP1_WAIT;
            end

            PRINT_OP1_WAIT: begin
                if (print_done) begin
                    // 根据操作类型决定下一步
                    case (op_code)
                        OP_TRANSPOSE, OP_SCALAR:
                            next_state = DONE;
                        OP_ADD, OP_MUL:
                            next_state = GEN_RAND_OP2;
                        default:
                            next_state = ERROR;
                    endcase
                end
            end

            GEN_RAND_OP2:
                next_state = QUERY_OP2;

            QUERY_OP2:
                next_state = CHECK_OP2_VALID;

            CHECK_OP2_VALID: begin
                // 检查该位置是否有元素
                if (op2_count == 2'd0) begin
                    // 该位置无元素，重新生成
                    if (retry_count < MAX_RETRY)
                        next_state = GEN_RAND_OP2;
                    else
                        next_state = ERROR;
                end else begin
                    // 该位置有元素，检查是否满足运算规则
                    // 假设维度对应：位置 i -> m = i/5, n = i%5
                    // 这里需要判断是否与 op1 的维度相匹配
                    next_state = READ_OP2;
                end
            end

            READ_OP2:
                next_state = PRINT_OP2;

            PRINT_OP2: begin
                if (!print_done)
                    next_state = PRINT_OP2_WAIT;
            end

            PRINT_OP2_WAIT: begin
                if (print_done)
                    next_state = DONE;
            end

            DONE:
                next_state = IDLE;

            ERROR:
                next_state = IDLE;

            default:
                next_state = IDLE;
        endcase
    end

    //================== 第三段：时序输出与数据路径 ==================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_en <= 1'b0;
            rd_col <= 3'd0;
            rd_row <= 3'd0;
            rd_mat_index <= 2'd0;
            
            sel_dim_m <= 3'd0;
            sel_dim_n <= 3'd0;
            sel_matrix <= 200'd0;
            sel_matrix_id <= 2'd0;
            sel_done <= 1'b0;
            sel_error <= 1'b0;
            
            print_start <= 1'b0;
            print_dim_m <= 3'd0;
            print_dim_n <= 3'd0;
            print_matrix <= 200'd0;
            
            query_index <= 2'd0;
            query_dim_m <= 3'd0;
            query_dim_n <= 3'd0;
            
            op1_pos <= 5'd0;
            op2_pos <= 5'd0;
            op1_m <= 3'd0;
            op1_n <= 3'd0;
            op2_m <= 3'd0;
            op2_n <= 3'd0;
            op1_matrix <= 200'd0;
            op2_matrix <= 200'd0;
            op1_id <= 2'd0;
            op2_id <= 2'd0;
            tried_positions <= 25'd0;
            retry_count <= 8'd0;
        end else begin
            // 默认清除脉冲信号
            read_en <= 1'b0;
            sel_done <= 1'b0;
            sel_error <= 1'b0;
            print_start <= 1'b0;

            case (state)
                IDLE: begin
                    tried_positions <= 25'd0;
                    retry_count <= 8'd0;
                end

                GEN_RAND_OP1: begin
                    // 生成随机位置
                    op1_pos <= rand_pos;
                    // 标记该位置已尝试
                    tried_positions[rand_pos] <= 1'b1;
                    retry_count <= retry_count + 1'b1;
                end

                QUERY_OP1: begin
                    // 查询该位置的矩阵维度和 ID
                    query_dim_m <= op1_pos / 5'd5;
                    query_dim_n <= op1_pos % 5'd5;
                    // 假设我们在这里查询两个槽位，选择有元素的那个
                    // 实际应该从 info_table 中提取
                end

                CHECK_OP1_EXISTS: begin
                    // 检查逻辑已在次态完成
                    if (op1_count != 2'd0) begin
                        op1_m <= op1_pos / 5'd5;
                        op1_n <= op1_pos % 5'd5;
                        // 决定从槽位 0 还是 1 读取
                        // 这里简化为交替选择或根据 info_table 选择
                        op1_id <= ((op1_count & 2'b01) != 0) ? 2'd0 : 2'd1;
                    end
                end

                READ_OP1: begin
                    read_en <= 1'b1;
                    rd_col <= op1_m;
                    rd_row <= op1_n;
                    rd_mat_index <= op1_id;
                end

                PRINT_OP1: begin
                    if (rd_ready) begin
                        // 锁存读到的数据
                        op1_matrix <= rd_data_flow;
                    end
                    print_start <= 1'b1;
                    print_dim_m <= op1_m;
                    print_dim_n <= op1_n;
                    print_matrix <= op1_matrix;
                end

                PRINT_OP1_WAIT: begin
                    // 等待打印完成
                end

                GEN_RAND_OP2: begin
                    // 生成第二个操作数的随机位置
                    op2_pos <= rand_pos;
                    tried_positions[rand_pos] <= 1'b1;
                    retry_count <= retry_count + 1'b1;
                end

                QUERY_OP2: begin
                    // 查询第二个位置
                    query_dim_m <= op2_pos / 5'd5;
                    query_dim_n <= op2_pos % 5'd5;
                end

                CHECK_OP2_VALID: begin
                    if (op2_count != 2'd0) begin
                        op2_m <= op2_pos / 5'd5;
                        op2_n <= op2_pos % 5'd5;
                        op2_id <= ((op2_count & 2'b01) != 0) ? 2'd0 : 2'd1;
                    end
                end

                READ_OP2: begin
                    read_en <= 1'b1;
                    rd_col <= op2_m;
                    rd_row <= op2_n;
                    rd_mat_index <= op2_id;
                end

                PRINT_OP2: begin
                    if (rd_ready) begin
                        op2_matrix <= rd_data_flow;
                    end
                    print_start <= 1'b1;
                    print_dim_m <= op2_m;
                    print_dim_n <= op2_n;
                    print_matrix <= op2_matrix;
                end

                PRINT_OP2_WAIT: begin
                    // 等待打印完成
                end

                DONE: begin
                    sel_done <= 1'b1;
                    sel_dim_m <= op1_m;
                    sel_dim_n <= op1_n;
                    sel_matrix <= op1_matrix;
                    sel_matrix_id <= op1_id;
                end

                ERROR: begin
                    sel_error <= 1'b1;
                end

                default: begin
                    // 默认处理
                end
            endcase
        end
    end

endmodule
