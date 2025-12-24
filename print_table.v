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
    localparam [7:0] ASCII_CR    = 8'h0D; // '\r'
    localparam [7:0] ASCII_LF    = 8'h0A; // '\n'

    // 状态定义
    localparam S_IDLE            = 4'd0,
               S_PREPARE_TOTAL   = 4'd1,
               S_PRINT_TOTAL_T   = 4'd2, // 打印 Total 十位
               S_PRINT_TOTAL_O   = 4'd3, // 打印 Total 个位
               S_GET_CELL        = 4'd4, // 准备矩阵单元数据
               S_PRINT_M         = 4'd5,
               S_PRINT_STAR1     = 4'd6,
               S_PRINT_N         = 4'd7,
               S_PRINT_STAR2     = 4'd8,
               S_PRINT_VAL       = 4'd9, // 打印表格内的 2-bit cnt
               S_PRINT_SPACE     = 4'd10,
               S_WAIT_TX         = 4'd11,
               S_DONE            = 4'd12,
               S_PRINT_CR        = 4'd13,
               S_PRINT_LF        = 4'd14;

    reg [3:0] state, next_state;
    reg [3:0] return_state; 
    reg [4:0] idx;
    reg [2:0] row, col;
    reg [7:0] t_cnt_tens, t_cnt_ones;
    reg [1:0] cell_val;
    reg cells_started; // 防止总数后的空格导致 idx 提前++
    // 基于 (col,row) 计算矩阵位置（与存储单元一致：列优先）
    wire [4:0] cur_place = (col - 3'd1) * 3'd5 + (row - 3'd1);

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
            S_GET_CELL:      next_state = S_PRINT_M;
            S_PRINT_M:       next_state = S_WAIT_TX;
            S_PRINT_STAR1:   next_state = S_WAIT_TX;
            S_PRINT_N:       next_state = S_WAIT_TX;
            S_PRINT_STAR2:   next_state = S_WAIT_TX;
            S_PRINT_VAL:     next_state = S_WAIT_TX;
            S_PRINT_SPACE:   next_state = S_WAIT_TX;
            S_PRINT_CR:      next_state = S_WAIT_TX;
            S_PRINT_LF:      next_state = S_WAIT_TX;

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
                            if (col == 5) next_state = S_PRINT_CR; // 行末先回车
                            else          next_state = S_GET_CELL;
                        end
                        S_PRINT_CR:      next_state = S_PRINT_LF; // 再换行
                        S_PRINT_LF: begin
                            if (idx == 25) next_state = S_DONE;   // 25 个单元完成
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
            cells_started <= 1'b0;
        end else begin
            uart_tx_en <= 0; // 默认不使能
            case (state)
                S_IDLE: begin
                    idx <= 0; row <= 1; col <= 1;
                    busy <= 0; done <= 0;
                    cells_started <= 1'b0;
                end

                S_PREPARE_TOTAL: begin
                    busy <= 1;
                    t_cnt_tens <= cnt / 10;
                    t_cnt_ones <= cnt % 10;
                end

                S_PRINT_TOTAL_T: begin
                    uart_tx_data <= ASCII_0 + t_cnt_tens;
                    return_state <= S_PRINT_TOTAL_T;
                end

                S_PRINT_TOTAL_O: begin
                    uart_tx_data <= ASCII_0 + t_cnt_ones;
                    return_state <= S_PRINT_TOTAL_O;
                end

                S_GET_CELL: begin
                    // MSB-first 读取：info_table[49:48] 是 count[0]，依次向下
                    cell_val <= info_table[49 - (cur_place*2) -: 2];
                    cells_started <= 1'b1;
                end

                S_PRINT_M: begin
                    uart_tx_data <= ASCII_0 + row;
                    return_state <= S_PRINT_M;
                end

                S_PRINT_STAR1, S_PRINT_STAR2: begin
                    uart_tx_data <= ASCII_STAR;
                    return_state <= state;
                end

                S_PRINT_N: begin
                    uart_tx_data <= ASCII_0 + col;
                    return_state <= S_PRINT_N;
                end

                S_PRINT_VAL: begin
                    uart_tx_data <= ASCII_0 + cell_val; // 这里是表格里的两位值
                    return_state <= S_PRINT_VAL;
                end

                S_PRINT_SPACE: begin
                    uart_tx_data <= ASCII_SPACE;
                    return_state <= S_PRINT_SPACE;
                end

                S_PRINT_CR: begin
                    uart_tx_data <= ASCII_CR;
                    return_state <= S_PRINT_CR;
                end

                S_PRINT_LF: begin
                    uart_tx_data <= ASCII_LF;
                    return_state <= S_PRINT_LF;
                end

                S_WAIT_TX: begin
                    uart_tx_en <= 0;
                    if (!uart_tx_busy) begin
                        uart_tx_en <= 1;
                        if (return_state == S_PRINT_SPACE && cells_started) begin
                            idx <= idx + 1;
                            if (col == 5) begin col <= 1; row <= row + 1; end
                            else          begin col <= col + 1; end
                        end
                    end
                end

                S_DONE: begin done <= 1; busy <= 0; end
            endcase
        end
    end

    // 接口同步（寄存调试信号，和发送脉冲对齐）
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout <= 8'd0;
            dout_valid <= 1'b0;
        end else begin
            if (uart_tx_en) begin
                dout <= uart_tx_data;
                dout_valid <= 1'b1;
            end else begin
                dout_valid <= 1'b0;
            end
        end
    end

endmodule