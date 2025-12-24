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
    input wire [7:0] cnt,     // 外部 cnt 作为表格前缀显示
    output reg busy,
    output reg done,
    output wire [3:0] current_state
);

    assign current_state = state;

    // --- ASCII 常量 ---
    localparam [7:0] ASCII_STAR  = 8'h2A, ASCII_SPACE = 8'h20,
                     ASCII_0     = 8'h30, ASCII_CR    = 8'h0D, ASCII_LF = 8'h0A;

    // --- 状态定义 ---
    localparam S_IDLE        = 4'd0,
               S_FETCH       = 4'd1, // 读取 2-bit 计数
               S_CHECK       = 4'd2, // 检查是否为 0
               S_SET_DATA    = 4'd3, // 准备 ASCII
               S_SEND_TRIG   = 4'd4, 
               S_WAIT_BUSY   = 4'd5, // 等待发送开始
               S_WAIT_DONE   = 4'd6, // 等待发送完成
               S_COOL_DOWN   = 4'd7, 
               S_NEXT_STEP   = 4'd8, // 推进单元和行列
               S_DONE        = 4'd9;

    reg [3:0] state, next_state;
    reg [3:0] step_cnt; 
    reg [4:0] cell_idx; 
    reg [2:0] row, col; 
    reg [7:0] t_tens, t_ones;
    reg [1:0] cur_cell_val;
    reg wait_tx_done; // 等待 uart_tx 完成当前字节
    reg send_done;    // 当前字符发送完成
    reg header_done; 
    // 发送字符间的冷却计数（可选）
    parameter integer COOL_TIME = 16'd1000; // 根据时钟与UART速率可适当调整
    reg [15:0] cool_cnt;

    // 计算当前 2-bit 在 info_table 中的位置
    wire [5:0] bit_pos = cell_idx << 1;

    // --- 第一段：同步状态转换 ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= next_state;
    end

    // --- 第二段：组合逻辑和转移 ---
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE:       if (start) next_state = S_FETCH;
            S_FETCH:      next_state = S_CHECK;
            S_CHECK: begin
                if (cur_cell_val == 2'd0) next_state = S_NEXT_STEP; // 计数为0直接跳过
                else                      next_state = S_SET_DATA;
            end
            S_SET_DATA:   next_state = S_SEND_TRIG;
            S_SEND_TRIG:  next_state = S_WAIT_BUSY;
            S_WAIT_BUSY:  if (uart_tx_busy)  
                next_state = S_WAIT_DONE;
            S_WAIT_DONE:  if (!uart_tx_busy) next_state = S_COOL_DOWN;
            S_COOL_DOWN:  if (cool_cnt >= COOL_TIME) next_state = S_NEXT_STEP;
            S_NEXT_STEP: begin
                // 当前单元（非0且未全输出）需要继续输出，则进入S_SET_DATA
                if (cur_cell_val != 2'd0 && step_cnt < 4'd8) next_state = S_SET_DATA;
                // 已处理完25个单元（cell_idx已达24），进入完成，防止继续读取超界
                else if (cell_idx >= 5'd24) next_state = S_DONE;
                // 否则准备读取下一个单元
                else next_state = S_FETCH;
            end
            S_DONE:       next_state = S_IDLE;
            default:      next_state = S_IDLE;
        endcase
    end

    // --- 第三段：时序逻辑和数据 ---
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
                    // 防护：不读超界
                    if (cell_idx < 5'd25) begin
                        cur_cell_val <= info_table[bit_pos +: 2];
                    end
                    // 简单的 BCD 转换实现 (cnt 为外部 8-bit 数值)
                    t_tens <= (cnt >= 90) ? 9 : (cnt >= 80) ? 8 : (cnt >= 70) ? 7 : (cnt >= 60) ? 6 : (cnt >= 50) ? 5 : (cnt >= 40) ? 4 : (cnt >= 30) ? 3 : (cnt >= 20) ? 2 : (cnt >= 10) ? 1 : 0;
                    t_ones <= cnt % 10;
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

                S_SEND_TRIG: uart_tx_en <= 1'b1;
                S_WAIT_BUSY: if(uart_tx_busy) uart_tx_en <= 1'b0;

                S_COOL_DOWN: cool_cnt <= cool_cnt + 1'b1;

                S_NEXT_STEP: begin
                    cool_cnt <= 0;
                    // 当前单元还需要输出更多字符，递增 step_cnt
                    if (cur_cell_val != 2'd0 && step_cnt < 4'd8) begin
                        step_cnt <= step_cnt + 1'b1;
                    end else if (cell_idx >= 5'd24) begin
                        // 已到第25个单元，停止递增，让组合逻辑跳DONE
                        // cell_idx保持24，不做任何修改
                    end else begin
                        // 转移到下一个单元
                        header_done <= 1'b1;
                        step_cnt <= header_done ? 4'd3 : 4'd0;
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
