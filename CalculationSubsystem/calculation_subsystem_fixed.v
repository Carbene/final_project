module calculator_subsystem (
    // 时钟与复位
    input  clk,
    input  rst_n,
    // 控制信号
    input  enable,           
    input  btn_confirm,  
    input  btn_restart,   
    input  [7:0] sw,
    
    // 与 selector_display 模块接口
    output reg selector_en,
    input  selector_done,
    input  selector_error,
    input  [199:0]  matrix,
    input  [2:0] dim_m,
    input  [2:0] dim_n,
    
    // 与倒计时模块接口
    output reg error_calculator,    
    input  timer_done,
    
    // 与 ALU/计算模块通信
    output reg [2:0] op_code,
    output reg start_calculation,
    output reg [2:0] m_a,
    output reg [2:0] n_a,
    output reg [199:0] matrix_a_flat,
    output reg [2:0] m_b,
    output reg [2:0] n_b,
    output reg [199:0] matrix_b_flat,
    output reg [7:0] scalar,
    input  [399:0] result_flat,
    input  [2:0] result_m,
    input  [2:0] result_n,
    input  done_calculation,
    input  busy_calculation,
    
    // 与矩阵内容显示模块通信
    output reg matrix_result_display_start,
    output reg [2:0] result_m_display,
    output reg [2:0] result_n_display,
    output reg [399:0] result_display,
    input  matrix_result_display_done,
    input  matrix_result_display_busy,
    
    // 模式能否退出
    output reg exitable
);

    //================== 状态定义 ==================
    localparam IDLE                 = 5'd0;
    localparam WAIT_OP_CODE         = 5'd1;   // 等待操作码输入
    localparam WAIT_INPUT_MODE      = 5'd2;   // 等待输入模式选择（手动/自动）
    localparam OP1_SEL              = 5'd3;   // 第一个操作数选择
    localparam OP1_WAIT             = 5'd4;   // 等待第一个操作数选择完成
    localparam BRANCH_OP            = 5'd5;   // 分支处理：根据操作类型决定下一步
    localparam OP2_SEL              = 5'd6;   // 第二个操作数选择（双目运算）
    localparam OP2_WAIT             = 5'd7;   // 等待第二个操作数选择完成
    localparam LOAD_SCALAR_CONFIRM  = 5'd8;   // 标量输入确认（标量乘法）
    localparam LOAD_SCALAR          = 5'd9;   // 加载标量值
    localparam VALIDATION           = 5'd10;  // 验证操作数维度
    localparam EXECUTE              = 5'd11;  // 执行计算
    localparam EXECUTE_WAIT         = 5'd12;  // 等待计算完成
    localparam PRINT_RESULT         = 5'd13;  // 准备显示结果
    localparam PRINT_RESULT_WAIT    = 5'd14;  // 等待结果显示完成
    localparam DONE                 = 5'd15;  // 计算完成
    localparam ERROR                = 5'd16;  // 错误状态
    localparam EXIT                 = 5'd17;  // 退出状态

    //================== 运算模式定义 ==================
    localparam OP_ADD       = 5'd1;    // 加法（双目）
    localparam OP_MUL       = 5'd2;    // 矩阵乘法（双目）
    localparam OP_SCALAR    = 5'd4;    // 标量乘法（单目）
    localparam OP_TRANSPOSE = 5'd8;    // 转置（单目）

    //================== ALU 操作码定义 ==================
    localparam ALU_OP_TRANSPOSE = 3'd0;
    localparam ALU_OP_ADD       = 3'd1;
    localparam ALU_OP_SCALAR    = 3'd2;
    localparam ALU_OP_MUL       = 3'd3;

    //================== 维度限制常数 ==================
    localparam MIN_DIM = 3'd1;
    localparam MAX_DIM = 3'd5;

    //================== 状态寄存器 ==================
    reg [4:0] state, next_state;
    reg [4:0] retry_target;          // 错误重试的目标状态
    reg [4:0] op_code_reg;           // 当前操作码
    reg [4:0] input_mode_reg;        // 输入模式：1=手动，0=自动
    
    //================== 倒计时边沿检测 ==================
    reg timer_done_d1;
    reg timer_done_d2;
    wire timer_done_edge;
    assign timer_done_edge = timer_done_d1 && !timer_done_d2;

    //================== 维度验证函数 ==================
    // 检查维度是否在有效范围内
    function is_valid_dim;
        input [2:0] dim;
        begin
            is_valid_dim = (dim >= MIN_DIM) && (dim <= MAX_DIM);
        end
    endfunction

    // 检查加法操作数维度
    function is_valid_add;
        input [2:0] m_a, n_a, m_b, n_b;
        begin
            is_valid_add = (m_a == m_b) && (n_a == n_b) &&
                          is_valid_dim(m_a) && is_valid_dim(n_a) &&
                          is_valid_dim(m_b) && is_valid_dim(n_b);
        end
    endfunction

    // 检查矩阵乘法操作数维度
    function is_valid_mul;
        input [2:0] m_a, n_a, m_b, n_b;
        begin
            is_valid_mul = (n_a == m_b) &&
                          is_valid_dim(m_a) && is_valid_dim(n_a) &&
                          is_valid_dim(m_b) && is_valid_dim(n_b);
        end
    endfunction

    // 检查标量乘法操作数维度
    function is_valid_scalar;
        input [2:0] m_a, n_a;
        input [7:0] scalar_val;
        begin
            is_valid_scalar = is_valid_dim(m_a) && is_valid_dim(n_a) && (scalar_val <= 8'd9);
        end
    endfunction

    // 检查转置操作数维度
    function is_valid_transpose;
        input [2:0] m_a, n_a;
        begin
            is_valid_transpose = is_valid_dim(m_a) && is_valid_dim(n_a);
        end
    endfunction

    //================== 第一段：状态寄存 ==================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            timer_done_d1 <= 1'b0;
            timer_done_d2 <= 1'b0;
        end else begin
            state <= next_state;
            timer_done_d1 <= timer_done;
            timer_done_d2 <= timer_done_d1;
        end
    end

    //================== 第二段：次态逻辑 ==================
    always @(*) begin
        next_state = state;
        
        // 倒计时超时时强制返回 IDLE
        if (timer_done_edge) begin
            next_state = IDLE;
        end else begin
            case (state)
                IDLE: begin
                    if (enable)
                        next_state = WAIT_OP_CODE;
                end

                WAIT_OP_CODE: begin
                    if (btn_confirm)
                        next_state = WAIT_INPUT_MODE;
                end

                WAIT_INPUT_MODE: begin
                    if (btn_confirm)
                        next_state = OP1_SEL;
                end

                OP1_SEL:
                    next_state = OP1_WAIT;

                OP1_WAIT: begin
                    if (selector_done)
                        next_state = BRANCH_OP;
                    else if (selector_error)
                        next_state = ERROR;
                end

                BRANCH_OP: begin
                    // 根据操作类型分支
                    case (op_code_reg)
                        OP_ADD, OP_MUL: begin
                            // 双目运算，如果是手动模式则需要选择第二个操作数
                            if (input_mode_reg)
                                next_state = OP2_SEL;
                            else
                                next_state = VALIDATION;  // 自动模式直接验证
                        end
                        OP_SCALAR: begin
                            // 标量乘法，需要输入标量
                            next_state = LOAD_SCALAR_CONFIRM;
                        end
                        OP_TRANSPOSE: begin
                            // 转置操作，直接验证
                            next_state = VALIDATION;
                        end
                        default:
                            next_state = IDLE;
                    endcase
                end

                OP2_SEL:
                    next_state = OP2_WAIT;

                OP2_WAIT: begin
                    if (selector_done)
                        next_state = VALIDATION;
                    else if (selector_error)
                        next_state = ERROR;
                end

                LOAD_SCALAR_CONFIRM: begin
                    if (btn_confirm)
                        next_state = LOAD_SCALAR;
                end

                LOAD_SCALAR:
                    next_state = VALIDATION;

                VALIDATION: begin
                    // 进行维度验证
                    case (op_code_reg)
                        OP_ADD: begin
                            if (is_valid_add(m_a, n_a, m_b, n_b))
                                next_state = EXECUTE;
                            else
                                next_state = ERROR;
                        end
                        OP_MUL: begin
                            if (is_valid_mul(m_a, n_a, m_b, n_b))
                                next_state = EXECUTE;
                            else
                                next_state = ERROR;
                        end
                        OP_SCALAR: begin
                            if (is_valid_scalar(m_a, n_a, scalar))
                                next_state = EXECUTE;
                            else
                                next_state = ERROR;
                        end
                        OP_TRANSPOSE: begin
                            if (is_valid_transpose(m_a, n_a))
                                next_state = EXECUTE;
                            else
                                next_state = ERROR;
                        end
                        default:
                            next_state = IDLE;
                    endcase
                end

                EXECUTE:
                    next_state = EXECUTE_WAIT;

                EXECUTE_WAIT: begin
                    if (done_calculation)
                        next_state = PRINT_RESULT;
                end

                PRINT_RESULT: begin
                    if (!matrix_result_display_busy)
                        next_state = PRINT_RESULT_WAIT;
                end

                PRINT_RESULT_WAIT: begin
                    if (matrix_result_display_done)
                        next_state = DONE;
                end

                DONE:
                    next_state = EXIT;

                ERROR:
                    next_state = retry_target;

                EXIT: begin
                    if (!enable)
                        next_state = IDLE;
                    else if (btn_restart)
                        next_state = OP1_SEL;
                end

                default:
                    next_state = IDLE;
            endcase
        end
    end

    //================== 第三段：时序输出与数据路径 ==================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            selector_en <= 1'b0;
            error_calculator <= 1'b0;
            start_calculation <= 1'b0;
            matrix_result_display_start <= 1'b0;
            exitable <= 1'b0;
            
            op_code <= ALU_OP_TRANSPOSE;
            op_code_reg <= 5'd0;
            input_mode_reg <= 1'b0;
            retry_target <= OP1_SEL;
            
            m_a <= 3'd0;
            n_a <= 3'd0;
            matrix_a_flat <= 200'd0;
            m_b <= 3'd0;
            n_b <= 3'd0;
            matrix_b_flat <= 200'd0;
            scalar <= 8'd0;
            
            result_m_display <= 3'd0;
            result_n_display <= 3'd0;
            result_display <= 400'd0;
        end else begin
            // 默认清除脉冲信号
            selector_en <= 1'b0;
            error_calculator <= 1'b0;
            start_calculation <= 1'b0;
            matrix_result_display_start <= 1'b0;
            exitable <= 1'b0;

            case (state)
                IDLE: begin
                    exitable <= 1'b1;
                    op_code_reg <= 5'd0;
                    input_mode_reg <= 1'b0;
                    m_a <= 3'd0;
                    n_a <= 3'd0;
                    matrix_a_flat <= 200'd0;
                    m_b <= 3'd0;
                    n_b <= 3'd0;
                    matrix_b_flat <= 200'd0;
                    scalar <= 8'd0;
                end

                WAIT_OP_CODE: begin
                    // 等待通过开关/按钮输入操作码
                    if (btn_confirm) begin
                        case (sw[3:0])
                            4'd1: op_code_reg <= OP_ADD;
                            4'd2: op_code_reg <= OP_MUL;
                            4'd4: op_code_reg <= OP_SCALAR;
                            4'd8: op_code_reg <= OP_TRANSPOSE;
                            default: op_code_reg <= 5'd0;
                        endcase
                    end
                end

                WAIT_INPUT_MODE: begin
                    // 等待输入模式选择：1=手动，0=自动（使用某个开关位判断）
                    if (btn_confirm) begin
                        input_mode_reg <= sw[5];  // 假设用开关5来选择手动/自动
                    end
                end

                OP1_SEL: begin
                    selector_en <= 1'b1;
                    retry_target <= OP1_SEL;
                end

                OP1_WAIT: begin
                    if (selector_done) begin
                        // 成功获得第一个操作数
                        matrix_a_flat <= matrix;
                        m_a <= dim_m;
                        n_a <= dim_n;
                    end
                end

                BRANCH_OP: begin
                    // 分支逻辑已在次态中处理
                end

                OP2_SEL: begin
                    selector_en <= 1'b1;
                    retry_target <= OP2_SEL;
                end

                OP2_WAIT: begin
                    if (selector_done) begin
                        // 成功获得第二个操作数
                        matrix_b_flat <= matrix;
                        m_b <= dim_m;
                        n_b <= dim_n;
                    end
                end

                LOAD_SCALAR_CONFIRM: begin
                    // 等待用户确认标量值
                    // 标量值通过开关输入：sw[3:0]
                end

                LOAD_SCALAR: begin
                    scalar <= {4'b0000, sw[3:0]};  // 标量值扩展至8位
                end

                VALIDATION: begin
                    // 维度验证在组合逻辑中进行，这里无需额外处理
                end

                EXECUTE: begin
                    // 配置 ALU 操作码并启动计算
                    case (op_code_reg)
                        OP_ADD:       op_code <= ALU_OP_ADD;
                        OP_MUL:       op_code <= ALU_OP_MUL;
                        OP_SCALAR:    op_code <= ALU_OP_SCALAR;
                        OP_TRANSPOSE: op_code <= ALU_OP_TRANSPOSE;
                        default:      op_code <= ALU_OP_TRANSPOSE;
                    endcase
                    start_calculation <= 1'b1;
                end

                EXECUTE_WAIT: begin
                    // 等待计算完成，无需额外操作
                end

                PRINT_RESULT: begin
                    matrix_result_display_start <= 1'b1;
                    result_m_display <= result_m;
                    result_n_display <= result_n;
                    result_display <= result_flat;
                end

                PRINT_RESULT_WAIT: begin
                    // 等待显示完成，无需额外操作
                end

                DONE: begin
                    exitable <= 1'b1;
                end

                ERROR: begin
                    error_calculator <= 1'b1;
                    // 错误会触发倒计时，倒计时结束时会回到 IDLE
                    // 或者通过 next_state = retry_target 重新尝试
                end

                EXIT: begin
                    exitable <= 1'b1;
                end

                default: begin
                    // 默认状态处理
                end
            endcase
        end
    end

endmodule
