module generation_subsystem#(
    parameter VALUE_MIN = 0,
    parameter VALUE_MAX = 9
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,

    output reg rd_en,
    input wire uart_rx_empty,
    input wire [7:0] uart_rx_data,
    
    output reg write_en,
    output reg [2:0]   dim_m_generation,            
    output reg [2:0]   dim_n_generation,
    output reg [199:0] result_matrix,
    output reg         done,
    output reg         error
);
    // 状态定义
    localparam IDLE                   = 4'd0;
    localparam START_RANDOM           = 4'd1;
    localparam LOAD_DIM_M             = 4'd2;
    localparam READ_DIM_M             = 4'd3;
    localparam LOAD_DIM_N             = 4'd4;
    localparam READ_DIM_N             = 4'd5;
    localparam LOAD_CNT               = 4'd6;
    localparam READ_CNT               = 4'd7;
    localparam GENERATE_MATRIX        = 4'd8;
    localparam WRITE_MATRIX           = 4'd9;
    localparam DONE                   = 4'd10;
    localparam ERROR                  = 4'd11;

    reg [3:0] state, next_state; 
    reg [2:0] m_cnt, n_cnt;
    reg [1:0] matrix_cnt;  // 当前生成的矩阵计数
    reg [1:0] total_matrix_cnt;  // 总共需要生成的矩阵数
    reg [15:0] lfsr;
    reg [7:0] element_buffer;
    reg [5:0] addr;
    //状态转移
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin 
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (enable) begin
                    next_state = START_RANDOM;
                end
            end
            START_RANDOM: begin
                next_state = LOAD_DIM_M;
            end
            LOAD_DIM_M: begin
                if (!uart_rx_empty)
                    next_state = READ_DIM_M;
            end
            READ_DIM_M: begin
                if (uart_rx_data >= 8'h31 && uart_rx_data <= 8'h35)  // '1' to '5'
                    next_state = LOAD_DIM_N;
                else 
                    next_state = ERROR;
            end
            LOAD_DIM_N: begin
                if (!uart_rx_empty)
                    next_state = READ_DIM_N;
            end
            READ_DIM_N: begin
                if (uart_rx_data >= 8'h31 && uart_rx_data <= 8'h35)  // '1' to '5'
                    next_state = LOAD_CNT;
                else 
                    next_state = ERROR;
            end
            LOAD_CNT: begin
                if (!uart_rx_empty)
                    next_state = READ_CNT;
            end
            READ_CNT: begin
                if (uart_rx_data >= 8'h31 && uart_rx_data <= 8'h32)  // '1' or '2'
                    next_state = GENERATE_MATRIX;
                else 
                    next_state = ERROR;
            end
            GENERATE_MATRIX: begin
                if (m_cnt == dim_m_generation && n_cnt == dim_n_generation) begin
                    next_state = WRITE_MATRIX;
                end
            end
            WRITE_MATRIX: begin
                if (matrix_cnt == total_matrix_cnt) begin
                    next_state = DONE;
                end else begin
                    next_state = GENERATE_MATRIX;  // 生成下一个矩阵
                end
            end
            DONE: begin
                next_state = IDLE;
            end
            ERROR: begin
                next_state = IDLE;
            end
        endcase
    end
    // 输出逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done <= 1'b0;
            error <= 1'b0;
            result_matrix <= 200'd0;
            lfsr <= 16'hACE1;  // 初始化LFSR种子
            element_buffer <= 8'd0;
            dim_m_generation <= 3'd0;
            dim_n_generation <= 3'd0;
            m_cnt <= 3'd0;
            n_cnt <= 3'd0;
            matrix_cnt <= 2'd0;
            total_matrix_cnt <= 2'd0;
            rd_en <= 1'b0;
            write_en <= 1'b0;
            addr <= 6'd0;
        end else begin
            // 默认值
            done <= 1'b0;
            error <= 1'b0;
            rd_en <= 1'b0;
            write_en <= 1'b0;
            
            // LFSR持续运行以提供随机性
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
            
            case (state)
                IDLE: begin
                    m_cnt <= 3'd0;
                    n_cnt <= 3'd0;
                    matrix_cnt <= 2'd0;
                    result_matrix <= 200'd0;
                end
                
                START_RANDOM: begin
                    // 准备读取维度信息
                end
                
                LOAD_DIM_M: begin
                    rd_en <= 1'b1;  // 请求读取 dim_m
                end
                
                READ_DIM_M: begin
                    if (uart_rx_data >= 8'h31 && uart_rx_data <= 8'h35) begin
                        dim_m_generation <= uart_rx_data - 8'h30;  // ASCII to number
                    end
                end
                
                LOAD_DIM_N: begin
                    rd_en <= 1'b1;  // 请求读取 dim_n
                end
                
                READ_DIM_N: begin
                    if (uart_rx_data >= 8'h31 && uart_rx_data <= 8'h35) begin
                        dim_n_generation <= uart_rx_data - 8'h30;  // ASCII to number
                    end
                end
                
                LOAD_CNT: begin
                    rd_en <= 1'b1;  // 请求读取 cnt
                end
                
                READ_CNT: begin
                    if (uart_rx_data >= 8'h31 && uart_rx_data <= 8'h32) begin
                        total_matrix_cnt <= uart_rx_data - 8'h30;  // ASCII to number (1 or 2)
                        m_cnt <= 3'd0;
                        n_cnt <= 3'd0;
                        matrix_cnt <= 2'd1;  // 开始生成第1个矩阵
                    end
                end
                
                GENERATE_MATRIX: begin
                    // 计算地址（组合逻辑）
                    addr <= (m_cnt * dim_n_generation) + n_cnt;
                    
                    // 生成随机元素
                    element_buffer <= (lfsr % (VALUE_MAX - VALUE_MIN + 1)) + VALUE_MIN;
                    
                    // 写入矩阵（下一周期addr和element_buffer都准备好）
                    if (m_cnt < dim_m_generation && n_cnt < dim_n_generation) begin
                        result_matrix[addr*8 +: 8] <= element_buffer;
                        
                        // 更新计数器
                        if (n_cnt == dim_n_generation - 1) begin
                            n_cnt <= 3'd0;
                            m_cnt <= m_cnt + 1'b1;
                        end else begin
                            n_cnt <= n_cnt + 1'b1;
                        end
                    end
                end
                
                WRITE_MATRIX: begin
                    write_en <= 1'b1;  // 写入存储系统
                    m_cnt <= 3'd0;
                    n_cnt <= 3'd0;
                    matrix_cnt <= matrix_cnt + 1'b1;
                    result_matrix <= 200'd0;  // 清空准备下一个矩阵
                end
                
                DONE: begin
                    done <= 1'b1;
                end
                
                ERROR: begin
                    error <= 1'b1;
                end
            endcase
        end
    end

endmodule