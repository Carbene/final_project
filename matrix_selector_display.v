module matrix_selector_display #(
    parameter MAX_DIM = 5,
    parameter MAX_MATRIX_ID = 2
)(
    input clk,
    input rst_n,
    input start,
    
    // 与 print_table 通信：显示所有矩阵列表
    output reg print_table_start,
    input print_table_busy,
    input print_table_done,
    
    // 与 UART 接收通信：获取用户输入的 m, n, id
    input [7:0] uart_input_data,
    input uart_input_valid,
    
    // 与 print_specified_dim_matrix 通信：显示指定维度矩阵
    output reg print_spec_start,
    output reg [2:0] spec_dim_m,
    output reg [2:0] spec_dim_n,
    input print_spec_busy,
    input print_spec_done,
    input print_spec_error,
    
    // 与 matrix_storage 通信：读取矩阵数据
    output reg read_en,
    output reg [2:0] rd_col,
    output reg [2:0] rd_row,
    output reg [1:0] rd_mat_index,
    input [199:0] rd_data_flow,
    input rd_ready,
    
    // 与 matrix_printer 通信：打印矩阵
    output reg matrix_print_start,
    output reg [199:0] matrix_flat,
    input matrix_print_busy,
    input matrix_print_done,
    
    // 输出状态
    output reg error,
    output reg done,
    output reg [9:0] selected_matrix_id  // {dim_m[2:0], dim_n[2:0], id[1:0]}
);

    localparam [7:0] MAX_DIM_ASCII = 8'h30 + MAX_DIM;
    localparam [7:0] MAX_ID_ASCII  = 8'h30 + MAX_MATRIX_ID;
    localparam [2:0] MAX_DIM_3B    = MAX_DIM[2:0];  // 参数值范围 1..5，收窄为 3 位

    // 状态定义
    localparam IDLE                     = 5'd0;
    localparam DISPLAY_TABLE            = 5'd1;
    localparam DISPLAY_TABLE_WAIT       = 5'd2;
    localparam INPUT_DIM_M              = 5'd3;
    localparam INPUT_DIM_M_WAIT         = 5'd4;
    localparam INPUT_DIM_N              = 5'd5;
    localparam INPUT_DIM_N_WAIT         = 5'd6;
    localparam CHECK_DIM_EXISTS         = 5'd7;  // 检查维度是否存在
    localparam DISPLAY_SPECIFIED        = 5'd8;
    localparam DISPLAY_SPECIFIED_WAIT   = 5'd9;
    localparam INPUT_ID                 = 5'd10;
    localparam INPUT_ID_WAIT            = 5'd11;
    localparam LOAD_MATRIX_REQ          = 5'd12;
    localparam LOAD_MATRIX_WAIT         = 5'd13;
    localparam DISPLAY_MATRIX           = 5'd14;
    localparam DISPLAY_MATRIX_WAIT      = 5'd15;
    localparam DONE_STATE               = 5'd16;
    localparam ERROR_STATE              = 5'd17;

    // 状态寄存器
    reg [4:0] state, next_state;
    
    // 缓存输入数据
    reg [2:0] dim_m_buffer, dim_n_buffer;
    reg [1:0] matrix_id_buffer;
    reg dim_m_valid, dim_n_valid, matrix_id_valid;  // 标记是否已采集到一位有效数字

    wire is_space = (uart_input_data == 8'h20);
    wire is_cr    = (uart_input_data == 8'h0D);
    wire is_lf    = (uart_input_data == 8'h0A);
    wire is_crlf  = is_cr || is_lf;

    wire valid_m_digit  = (uart_input_data >= 8'h31) && (uart_input_data <= MAX_DIM_ASCII);
    wire valid_n_digit  = valid_m_digit;
    wire valid_id_digit = (uart_input_data >= 8'h31) && (uart_input_data <= MAX_ID_ASCII);

    // --- 第一段：状态转换 ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else        state <= next_state;
    end

    // --- 第二段：下一状态逻辑 ---
    always @(*) begin
        next_state = state;
        case (state)
            IDLE:
                if (start)
                    next_state = DISPLAY_TABLE;
            
            DISPLAY_TABLE:
                if (!print_table_busy)
                    next_state = DISPLAY_TABLE_WAIT;
            
            DISPLAY_TABLE_WAIT:
                if (print_table_done)
                    next_state = INPUT_DIM_M;
            
            INPUT_DIM_M:
                next_state = INPUT_DIM_M_WAIT;  // 进入等待用户输入状态
            
            INPUT_DIM_M_WAIT: begin
                if (uart_input_valid) begin
                    if (!dim_m_valid) begin
                        // 仅接受一位 1..MAX_DIM
                        if (valid_m_digit)
                            next_state = INPUT_DIM_M_WAIT;  // 等待分隔符
                        else
                            next_state = ERROR_STATE;  // 非法或缺失输入
                    end else begin
                        // 已有一位数字，仅接受空格作为分隔符
                        if (is_space)
                            next_state = INPUT_DIM_N;
                        else
                            next_state = ERROR_STATE;  // 多位数字或错误分隔
                    end
                end
            end
            
            INPUT_DIM_N:
                next_state = INPUT_DIM_N_WAIT;
            
            INPUT_DIM_N_WAIT: begin
                if (uart_input_valid) begin
                    if (!dim_n_valid) begin
                        if (valid_n_digit)
                            next_state = INPUT_DIM_N_WAIT;
                        else
                            next_state = ERROR_STATE;
                    end else begin
                        if (is_space)
                            next_state = CHECK_DIM_EXISTS;
                        else
                            next_state = ERROR_STATE;
                    end
                end
            end
            
            CHECK_DIM_EXISTS:
                // 这个状态检查维度是否有效，直接进入显示
                if (dim_m_valid && dim_n_valid && dim_m_buffer >= 3'd1 && dim_m_buffer <= MAX_DIM_3B
                    && dim_n_buffer >= 3'd1 && dim_n_buffer <= MAX_DIM_3B)
                    next_state = DISPLAY_SPECIFIED;
                else
                    next_state = ERROR_STATE;
            
            DISPLAY_SPECIFIED:
                if (!print_spec_busy)
                    next_state = DISPLAY_SPECIFIED_WAIT;
            
            DISPLAY_SPECIFIED_WAIT: begin
                if (print_spec_done)
                    next_state = INPUT_ID;
                else if (print_spec_error)
                    next_state = ERROR_STATE;
            end
            
            INPUT_ID:
                next_state = INPUT_ID_WAIT;
            
            INPUT_ID_WAIT: begin
                if (uart_input_valid) begin
                    if (!matrix_id_valid) begin
                        if (valid_id_digit)
                            next_state = INPUT_ID_WAIT;  // 等待行结束
                        else
                            next_state = ERROR_STATE;     // 非法或缺失输入
                    end else begin
                        if (is_crlf)
                            next_state = LOAD_MATRIX_REQ;
                        else
                            next_state = ERROR_STATE;     // 追加多位或错误分隔
                    end
                end
            end
            
            LOAD_MATRIX_REQ:
                if (rd_ready)
                    next_state = LOAD_MATRIX_WAIT;
            
            LOAD_MATRIX_WAIT:
                if (rd_ready)
                    next_state = DISPLAY_MATRIX;
            
            DISPLAY_MATRIX:
                if (!matrix_print_busy)
                    next_state = DISPLAY_MATRIX_WAIT;
            
            DISPLAY_MATRIX_WAIT:
                if (matrix_print_done)
                    next_state = DONE_STATE;
            
            DONE_STATE:
            if(!start)
                next_state = IDLE;
            
            ERROR_STATE:
                next_state = IDLE;
            
            default:
                next_state = IDLE;
        endcase
    end

    // --- 第三段：时序输出与数据路径 ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            print_table_start <= 1'b0;
            print_spec_start <= 1'b0;
            spec_dim_m <= 3'd0;
            spec_dim_n <= 3'd0;
            read_en <= 1'b0;
            rd_col <= 3'd0;
            rd_row <= 3'd0;
            rd_mat_index <= 2'd0;
            matrix_print_start <= 1'b0;
            matrix_flat <= 200'd0;
            error <= 1'b0;
            done <= 1'b0;
            selected_matrix_id <= 10'd0;
            dim_m_buffer <= 3'd0;
            dim_n_buffer <= 3'd0;
            matrix_id_buffer <= 2'd0;
            dim_m_valid <= 1'b0;
            dim_n_valid <= 1'b0;
            matrix_id_valid <= 1'b0;
        end else begin
            // 默认清除脉冲信号
            print_table_start <= 1'b0;
            print_spec_start <= 1'b0;
            read_en <= 1'b0;
            matrix_print_start <= 1'b0;
            error <= 1'b0;
            done <= 1'b0;
            
            case (state)
                DISPLAY_TABLE: begin
                    print_table_start <= 1'b1;  // 脉冲启动表格显示
                    dim_m_buffer <= 3'd0;
                    dim_n_buffer <= 3'd0;
                    matrix_id_buffer <= 2'd0;
                    dim_m_valid <= 1'b0;
                    dim_n_valid <= 1'b0;
                    matrix_id_valid <= 1'b0;
                end
                
                INPUT_DIM_M: begin // 请求用户输入 m
                end
                
                INPUT_DIM_M_WAIT: begin
                    if (uart_input_valid && valid_m_digit && !dim_m_valid) begin
                        // 接收一位有效数字（1..MAX_DIM）
                        dim_m_buffer <= uart_input_data - 8'h30;
                        dim_m_valid <= 1'b1;
                    end
                end
                
                INPUT_DIM_N: begin
                end
                
                INPUT_DIM_N_WAIT: begin
                    if (uart_input_valid && valid_n_digit && !dim_n_valid) begin
                        dim_n_buffer <= uart_input_data - 8'h30;
                        dim_n_valid <= 1'b1;
                    end
                end
                
                DISPLAY_SPECIFIED: begin
                    spec_dim_m <= dim_m_buffer;
                    spec_dim_n <= dim_n_buffer;
                    print_spec_start <= 1'b1;  // 脉冲启动指定维度显示
                end
                
                INPUT_ID: begin
                end
                
                INPUT_ID_WAIT: begin
                    if (uart_input_valid && valid_id_digit && !matrix_id_valid) begin
                        // 接收一位有效数字（1..MAX_MATRIX_ID），内部转为 0-based
                        matrix_id_buffer <= uart_input_data - 8'h31;
                        matrix_id_valid <= 1'b1;
                    end
                end
                
                LOAD_MATRIX_REQ: begin
                    read_en <= 1'b1;
                    rd_col <= dim_m_buffer;
                    rd_row <= dim_n_buffer;
                    rd_mat_index <= matrix_id_buffer;
                end
                
                DISPLAY_MATRIX: begin
                    matrix_flat <= rd_data_flow;
                    matrix_print_start <= 1'b1;  // 脉冲启动矩阵打印
                end
                
                DONE_STATE: begin
                    selected_matrix_id <= {dim_m_buffer, dim_n_buffer, matrix_id_buffer};
                    done <= 1'b1;
                    dim_m_valid <= 1'b0;
                    dim_n_valid <= 1'b0;
                    matrix_id_valid <= 1'b0;
                end
                
                ERROR_STATE: begin
                    error <= 1'b1;
                    dim_m_valid <= 1'b0;
                    dim_n_valid <= 1'b0;
                    matrix_id_valid <= 1'b0;
                end
            endcase
        end
    end

endmodule
