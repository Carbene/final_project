module print_table(
    input wire clk,
    input wire rst_n,
    input wire start,
    // UART TX 接口
    input wire uart_tx_busy,
    output reg uart_tx_en,
    output reg [7:0] uart_tx_data,
    input wire [49:0] info_table,
    input wire [7:0] cnt,        // 外部输入的 total_cnt
    output reg busy,
    output reg done,
    output reg [7:0] dout,       // 调试输出
    output reg dout_valid
);

    // ASCII 常量
    localparam [7:0] ASCII_STAR  = 8'h2A; // '*'
    localparam [7:0] ASCII_SPACE = 8'h20; // ' '
    localparam [7:0] ASCII_0     = 8'h30;

    // 状态定义
    localparam S_IDLE            = 4'd0,
               S_PREPARE_TOTAL   = 4'd1,
               S_PRINT_TOTAL_T   = 4'd2, // 打印 Total 十位
               S_PRINT_TOTAL_O   = 4'd3, // 打印 Total 个位
               S_GET_CELL        = 4'd5, // 准备矩阵单元数据
               S_PRINT_M         = 4'd6,
               S_PRINT_STAR1     = 4'd7,
               S_PRINT_N         = 4'd8,
               S_PRINT_STAR2     = 4'd9,
               S_PRINT_VAL       = 4'd10, // 打印表格内的 2-bit cnt
               S_PRINT_SPACE     = 4'd11,
               S_WAIT_TX         = 4'd12,
               S_DONE            = 4'd13;

    reg [3:0] state, next_state;
    reg [3:0] return_state; 
    reg [4:0] idx;
    reg [2:0] row, col;
    reg [7:0] t_cnt_tens, t_cnt_ones;
    reg [1:0] cell_val;

    // --- 第一段：时序逻辑 ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= next_state;
    end

    // --- 第二段：组合逻辑 (状态转移) ---
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE:          if (start) next_state = S_PREPARE_TOTAL;
            S_PREPARE_TOTAL: next_state = S_PRINT_TOTAL_T;
            
            S_PRINT_TOTAL_T: next_state = S_WAIT_TX;
            S_PRINT_TOTAL_O: next_state = S_WAIT_TX;
            S_PRINT_NEWLINE: next_state = S_WAIT_TX;
            
            S_GET_CELL:      next_state = S_PRINT_M;
            S_PRINT_M:       next_state = S_WAIT_TX;
            S_PRINT_STAR1:   next_state = S_WAIT_TX;
            S_PRINT_N:       next_state = S_WAIT_TX;
            S_PRINT_STAR2:   next_state = S_WAIT_TX;
            S_PRINT_VAL:     next_state = S_WAIT_TX;
            S_PRINT_SPACE:   next_state = S_WAIT_TX;

            S_WAIT_TX: begin
                if (!uart_tx_busy) begin
                    case (return_state)
                        S_PRINT_TOTAL_T: next_state = S_PRINT_TOTAL_O;
                        S_PRINT_TOTAL_O: next_state = S_PRINT_SPACE;
                        S_PRINT_M:       next_state = S_PRINT_STAR1;
                        S_PRINT_STAR1:   next_state = S_PRINT_N;
                        S_PRINT_N:       next_state = S_PRINT_STAR2;
                        S_PRINT_STAR2:   next_state = S_PRINT_VAL;
                        S_PRINT_VAL:     next_state = S_PRINT_SPACE;
                        S_PRINT_SPACE: begin
                            if (idx == 24) next_state = S_DONE;
                            else           next_state = S_GET_CELL;
                        end
                        default:         next_state = S_IDLE;
                    endcase
                end
            end
            S_DONE:          next_state = S_IDLE;
            default:         next_state = S_IDLE;
        endcase
    end

    // --- 第三段：输出与数据路径 ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idx <= 0; row <= 1; col <= 1;
            uart_tx_en <= 0; busy <= 0; done <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    idx <= 0; row <= 1; col <= 1;
                    busy <= 0; done <= 0;
                    uart_tx_en <= 0;
                end

                S_PREPARE_TOTAL: begin
                    busy <= 1;
                    t_cnt_tens <= cnt / 10;
                    t_cnt_ones <= cnt % 10;
                end

                S_PRINT_TOTAL_T: begin
                    uart_tx_data <= ASCII_0 + t_cnt_tens;
                    uart_tx_en   <= 1;
                    return_state <= S_PRINT_TOTAL_T;
                end

                S_PRINT_TOTAL_O: begin
                    uart_tx_data <= ASCII_0 + t_cnt_ones;
                    uart_tx_en   <= 1;
                    return_state <= S_PRINT_TOTAL_O;
                end

                S_GET_CELL: begin
                    cell_val <= info_table[idx*2 +: 2];
                end

                S_PRINT_M: begin
                    uart_tx_data <= ASCII_0 + row;
                    uart_tx_en   <= 1;
                    return_state <= S_PRINT_M;
                end

                S_PRINT_STAR1, S_PRINT_STAR2: begin
                    uart_tx_data <= ASCII_STAR;
                    uart_tx_en   <= 1;
                    return_state <= state;
                end

                S_PRINT_N: begin
                    uart_tx_data <= ASCII_0 + col;
                    uart_tx_en   <= 1;
                    return_state <= S_PRINT_N;
                end

                S_PRINT_VAL: begin
                    uart_tx_data <= ASCII_0 + cell_val; // 这里是表格里的两位值
                    uart_tx_en   <= 1;
                    return_state <= S_PRINT_VAL;
                end

                S_PRINT_SPACE: begin
                    uart_tx_data <= ASCII_SPACE;
                    uart_tx_en   <= 1;
                    return_state <= S_PRINT_SPACE;
                end

                S_WAIT_TX: begin
                    uart_tx_en <= 0;
                    if (!uart_tx_busy && return_state == S_PRINT_SPACE) begin
                        idx <= idx + 1;
                        if (col == 5) begin col <= 1; row <= row + 1; end
                        else          begin col <= col + 1; end
                    end
                end

                S_DONE: begin done <= 1; busy <= 0; end
            endcase
        end
    end

    // 接口同步
    always @(*) begin
        dout = uart_tx_data;
        dout_valid = uart_tx_en;
    end

endmodule