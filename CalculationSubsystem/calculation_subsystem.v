module calculator_subsystem (
    // 时钟与复位
    input  clk,
    input  rst_n,
    // 控制信号
    input  enable,           
    input  btn_confirm,  
    input btn_restart,   
    input  [4:0]  sw,
    // 选择器模块接口
    output reg selector_en,
    input  selector_done,
    input  selector_error,
    input  [199:0]  matrix,
    input [2:0] dim_m,
    input [2:0] dim_n,
    // 外部计时器模块接口
    output reg error_calculator,    
    input  timer_done,
    //与计算结果模块通信
    output [2:0] op_code,
    output reg start_calculation,
    output reg [2:0] m_a,
    output reg [2:0] n_a,
    output reg [199:0] matrix_a_flat,
    output reg [2:0] m_b,
    output reg [2:0] n_b,
    output reg [199:0] matrix_b_flat,
    output reg [7:0] scalar,
    input wire [399:0] result_flat,
    input wire [2:0] result_m,
    input wire [2:0] result_n,
    input wire done_calculation,
    input wire busy,
    // 与矩阵内容显示模块通信
    output reg matrix_result_display_start,
    output reg [2:0] result_m_display,
    output reg [2:0] result_n_display,
    output reg [399:0] result_display,
    input matrix_result_display_done,
    input matrix_result_display_busy,
    // 能不能退出切换到别的模式 
    output reg exitable
);
    //状态定义
    localparam IDLE                 = 4'd0;
    localparam WAIT_MODE            = 4'd1;
    localparam OP1_SEL              = 4'd2;
    localparam OP1_WAIT             = 4'd3;
    localparam BRANCH_OP            = 4'd4;
    localparam OP2_SEL              = 4'd5;
    localparam OP2_WAIT             = 4'd6;
    localparam LOAD_SCALAR_CONFIRM  = 4'd7;
    localparam LOAD_SCALAR          = 4'd8;
    localparam VALIDATION           = 4'd9;
    localparam EXECUTE              = 4'd10;
    localparam DONE                 = 4'd11;
    localparam ERROR                = 4'd12;
    localparam PRINT_RESULT         = 4'd13;
    localparam PRINT_RESULT_WAIT    = 4'd14;
    localparam EXIT                 = 4'd15;
    //运算模式定义
    localparam MODE_ADD         = 5'd1;
    localparam MODE_MUL         = 5'd2;
    localparam MODE_SCALAR      = 5'd4;
    localparam MODE_TRANS       = 5'd8;
    // ALU操作码定义（与matrix_alu一致）
    localparam OP_CODE_TRANSPOSE  = 3'd0;
    localparam OP_CODE_ADD        = 3'd1;
    localparam OP_CODE_SCALAR     = 3'd2;
    localparam OP_CODE_MUL        = 3'd3;
    //状态寄存器
    reg [3:0] state, next_state, retry_target;
    // 模式寄存器
    reg [4:0] mode_reg;
    reg timer_done_d1; // timer_done 的第一拍延迟
    reg timer_done_d2; // timer_done 的第二拍延迟
    wire timer_done_edge; // 检测到的边沿脉冲
    assign timer_done_edge = timer_done_d1 && !timer_done_d2;
    //状态转移
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
    //次态逻辑
    always @(*) begin
        next_state = state;
        if (timer_done_edge) 
            next_state = IDLE;
        else begin
        case (state)
            IDLE:      
                if (enable) 
                next_state = WAIT_MODE;
            WAIT_MODE: begin
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
                case (mode_reg)
                    MODE_ADD, MODE_MUL:    
                        next_state = OP2_SEL;
                    MODE_SCALAR:           
                        next_state = LOAD_SCALAR_CONFIRM;
                    MODE_TRANS: 
                        next_state = VALIDATION;
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
            LOAD_SCALAR_CONFIRM: 
                if (btn_confirm) 
                    next_state = LOAD_SCALAR;
            LOAD_SCALAR: next_state = VALIDATION;
            VALIDATION: begin
                case (mode_reg)
                    MODE_ADD: 
                        if (m_a == m_b && n_a == n_b) 
                            next_state = EXECUTE;
                        else 
                            next_state = ERROR;
                    MODE_MUL:
                        if (n_a == m_b) 
                            next_state = EXECUTE;
                        else 
                            next_state = ERROR;
                    MODE_SCALAR:
                        if(scalar > 9)
                            next_state = ERROR;
                        else
                            next_state = EXECUTE;
                    default: 
                        next_state = EXECUTE;
                endcase
            end
            ERROR: 
                    next_state = retry_target;
            EXECUTE:    
                if (done) 
                    next_state = PRINT_RESULT;
            PRINT_RESULT: begin
                if(!matrix_result_display_busy) 
                    next_state = PRINT_RESULT_WAIT;
            end
            PRINT_RESULT_WAIT: begin
                if (matrix_result_display_done) begin
                    next_state = DONE;
                end
            end
            DONE:
                next_state = EXIT;
            EXIT:
                if(!enable) 
                    next_state = IDLE;
                else if (btn_restart) 
                    next_state = OP1_SEL;
            default:    
                next_state = IDLE;
        endcase
        end
    end
    //输出逻辑与状态操作
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            selector_en <= 1'b0;
            error <= 1'b0;
            retry_target <= OP1_SEL;
            matrix_result_display_start <= 1'b0;
            mode_reg <= 5'd0;
            calculation_display <= 3'd0;
            exitable <= 1'b0;
            op_code <= 3'd0;
            start_calculation <= 1'b0;
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
            // 默认低电平脉冲控制
            selector_en <= 1'b0;
            error <= 1'b0;
            matrix_result_display_start <= 1'b0;
            exitable <= 1'b0;
            start <= 1'b0;
            case (state)
                IDLE: begin
                    matrix_result_display_start <= 1'b0;
                    exitable <= 1'b1;
                end
                WAIT_MODE: begin
                    if (btn_confirm) begin
                        if(sw[4:0] == 5'd1)
                            mode_reg <= MODE_ADD;
                        else if(sw[4:0] == 5'd2)
                            mode_reg <= MODE_MUL;
                        else if(sw[4:0] == 5'd4)
                            mode_reg <= MODE_SCALAR;
                        else
                            mode_reg <= MODE_TRANS;
                    end
                end
                OP1_SEL: begin 
                    selector_en <= 1'b1;
                    calculation_display <= mode_reg;
                end
                OP1_WAIT: begin
                    retry_target <= OP1_SEL; // 记录重试点
                    if (selector_done) begin
                        // 锁存A操作数
                        matrix_a_flat <= matrix;
                        m_a <= dim_m;
                        n_a <= dim_n;
                        error_calculator <= 1'b0;
                        end
                end
                OP2_SEL: begin
                    selector_en <= 1'b1;
                end
                OP2_WAIT: begin
                    retry_target <= OP2_SEL; // 记录重试点
                    if (selector_done) begin
                        // 锁存B操作数
                        matrix_b_flat <= matrix;
                        m_b <= dim_m;
                        n_b <= dim_n;
                        error_calculator <= 1'b0;
                        end
                end
                LOAD_SCALAR_CONFIRM: begin
                    // do nothing, just wait for btn_confirm
                end
                LOAD_SCALAR: begin
                    // 使用开关作为简单标量输入源（扩展至8位）
                    scalar <= {3'b000, sw};
                end
                VALIDATION: begin
                    // do nothing, just wait for next state
                end
                ERROR: begin
                    error    <= 1'b1;
                end
                EXECUTE: begin
                    // 配置ALU操作类型并启动
                    case (mode_reg)
                        MODE_ADD:    op_code <= OP_CODE_ADD;
                        MODE_MUL:    op_code <= OP_CODE_MUL;
                        MODE_SCALAR: op_code <= OP_CODE_SCALAR;
                        default:     op_code <= OP_CODE_TRANSPOSE;
                    endcase
                    start <= 1'b1;
                end
                PRINT_RESULT: begin
                    matrix_result_display_start <= 1'b1;
                    dim_m_display <= result_m;
                    dim_n_display <= result_n;
                    result_display <= result_flat;
                end
                PRINT_RESULT_WAIT: begin
                    // do nothing, just wait for matrix display done
                end
                DONE: 
                    exitable <= 1'b1;//do nothing, just wait for start signal to be low
                EXIT: 
                    exitable <= 1'b1;
            endcase
            // 特殊情况处理：如果在等待过程中选择器报错，立即触发错误逻辑
            if (selector_error) begin
                error <= 1'b1;
            end
        end
    end
endmodule