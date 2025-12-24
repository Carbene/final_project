module print_table(
    input wire clk,           
    input wire rst_n,
    input wire start,         
    // UART TX 接口
    input wire uart_tx_busy,
    output reg uart_tx_en,
    output reg [7:0] uart_tx_data,
    // 数据输入
    input wire [49:0] info_table,
    input wire [7:0] cnt,     // 这里的 cnt 作为总数前缀发送
    output reg busy,
    output reg done,
    output wire [3:0] current_state
);

    assign current_state = state;

    // --- ASCII 常量 ---
    localparam [7:0] ASCII_STAR  = 8'h2A, ASCII_SPACE = 8'h20,
                     ASCII_0     = 8'h30, ASCII_CR    = 8'h0D, ASCII_LF = 8'h0A;

    // --- 状态机定义 ---
    localparam S_IDLE        = 4'd0,
               S_FETCH       = 4'd1, // 提取 2-bit 数据
               S_CHECK       = 4'd2, // 检查是否为 0
               S_SET_DATA    = 4'd3, // 准备 ASCII
               S_SEND        = 4'd4, // 发送状态，类似 matrix_printer 的 SEND
               S_NEXT_STEP   = 4'd5, // 步进控制核心
               S_DONE        = 4'd6;

    reg [3:0] state, next_state;
    reg [3:0] step_cnt; 
    reg [4:0] cell_idx; 
    reg [2:0] row, col; 
    reg [7:0] t_tens, t_ones;
    reg [1:0] cur_cell_val;
    reg wait_tx_done; // 等待 uart_tx 完成当前字节
    reg send_done;    // 当前字符发送完成
    reg header_done; 

    // 计算当前 2-bit 在 info_table 中的位置
    wire [5:0] bit_pos = cell_idx << 1;

    // --- 第一段：同步状态切换 ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= next_state;
    end

    // --- 第二段：组合逻辑跳转 ---
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE:       if (start) next_state = S_FETCH;
            S_FETCH:      next_state = S_CHECK;
            S_CHECK: begin
                if (cur_cell_val == 2'd0) next_state = S_NEXT_STEP; // 关键：为0直接跳过发送
                else                      next_state = S_SET_DATA;
            end
            S_SET_DATA:   next_state = S_SEND;
            S_SEND:       next_state = send_done ? S_NEXT_STEP : S_SEND;
            S_NEXT_STEP: begin
                // 如果当前单元格需要发送且字符没发完，回 SET_DATA
                if (cur_cell_val != 2'd0 && step_cnt < 4'd8) next_state = S_SET_DATA;
                // 如果 25 个单元格全跑完了，去 DONE
                else if (cell_idx >= 5'd24) next_state = S_DONE;
                // 否则，取下一个单元格数据
                else next_state = S_FETCH;
            end
            S_DONE:       next_state = S_IDLE;
            default:      next_state = S_IDLE;
        endcase
    end

    // --- 第三段：时序逻辑输出 ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_tx_en <= 0; uart_tx_data <= 0; busy <= 0; done <= 0;
            step_cnt <= 0; cell_idx <= 0; row <= 1; col <= 1;
            wait_tx_done <= 1'b0; send_done <= 1'b0; header_done <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    busy <= 0; done <= 0; step_cnt <= 0; cell_idx <= 0;
                    row <= 1; col <= 1; wait_tx_done <= 1'b0; send_done <= 1'b0;
                    uart_tx_en <= 0; header_done <= 0;
                end

                S_FETCH: begin
                    busy <= 1;
                    // 使用 slice 获取当前单元格的值
                    cur_cell_val <= info_table[bit_pos +: 2];
                    // 简单的 BCD 转换实现 (cnt 为输入 8-bit 总数)
                    t_tens <= (cnt >= 90) ? 9 : (cnt >= 80) ? 8 : (cnt >= 70) ? 7 : (cnt >= 60) ? 6 : (cnt >= 50) ? 5 : (cnt >= 40) ? 4 : (cnt >= 30) ? 3 : (cnt >= 20) ? 2 : (cnt >= 10) ? 1 : 0;
                    t_ones <= cnt % 10; // 较小的常数取模在100M下通常安全
                end

                S_SET_DATA: begin
                    send_done <= 1'b0; // 重置发送完成标志
                    case (step_cnt)
                        4'd0:  uart_tx_data <= ASCII_0 + t_tens;
                        4'd1:  uart_tx_data <= ASCII_0 + t_ones;
                        4'd2:  uart_tx_data <= ASCII_SPACE;
                        4'd3:  uart_tx_data <= ASCII_0 + row;
                        4'd4:  uart_tx_data <= ASCII_STAR;
                        4'd5:  uart_tx_data <= ASCII_0 + col;
                        4'd6:  uart_tx_data <= ASCII_STAR;
                        4'd7:  uart_tx_data <= ASCII_0 + cur_cell_val;
                        default: uart_tx_data <= ASCII_SPACE;
                    endcase
                end

                S_SEND: begin
                    if (!wait_tx_done && !uart_tx_busy && !send_done) begin
                        // 发送当前字节
                        uart_tx_en   <= 1'b1;
                        wait_tx_done <= 1'b1;
                    end else if (wait_tx_done && uart_tx_busy) begin
                        // uart_tx 已响应，清除 start
                        uart_tx_en <= 1'b0;
                    end else if (wait_tx_done && !uart_tx_busy && uart_tx_en == 1'b0) begin
                        // uart_tx 完成发送（tx_busy 回落），准备下一个
                        wait_tx_done <= 1'b0;
                        send_done    <= 1'b1;
                    end
                end

                S_NEXT_STEP: begin
                    send_done <= 1'b0; // 重置
                    // 如果当前单元格需要发送且字符没发完，步进 step_cnt
                    if (cur_cell_val != 2'd0 && step_cnt < 4'd8) begin
                        step_cnt <= step_cnt + 1'b1;
                    end else begin
                        // 切换到下一个单元格逻辑
                        header_done <= 1'b1;
                        step_cnt <= header_done ? 4'd3 : 4'd0; // 如果是第一次，下一步是发送第一字符
                        cell_idx <= cell_idx + 1'b1;
                        if (col < 3'd5) col <= col + 1'b1;
                        else begin
                            col <= 1;
                            row <= row + 1'b1;
                        end
                    end
                end

                S_DONE: begin
                    done <= 1'b1;
                    busy <= 0;
                end
            endcase
        end
    end

endmodule