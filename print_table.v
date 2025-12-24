module print_table(
    input wire clk,           // 请确认时钟频率，默认按 100MHz 编写
    input wire rst_n,
    input wire start,         // 外部触发脉冲
    // UART TX 接口
    input wire uart_tx_busy,
    output reg uart_tx_en,
    output reg [7:0] uart_tx_data,
    // 数据输入
    input wire [49:0] info_table,
    input wire [7:0] cnt,     
    output reg busy,
    output reg done,
    output reg [3:0] current_state
);

    // --- ASCII 常量 ---
    localparam [7:0] ASCII_STAR  = 8'h2A, ASCII_SPACE = 8'h20,
                     ASCII_0     = 8'h30, ASCII_CR    = 8'h0D, ASCII_LF = 8'h0A;

    // --- 状态机定义 ---
    localparam S_IDLE        = 4'd0,
               S_PREPARE     = 4'd1,
               S_SET_DATA    = 4'd2,
               S_SEND_TRIG   = 4'd3,
               S_WAIT_START  = 4'd4, // 等待 busy 拉高
               S_WAIT_DONE   = 4'd5, // 等待 busy 拉低
               S_COOL_DOWN   = 4'd6, // 强制冷却，防止数据连喷导致乱码
               S_DONE        = 4'd7;

    reg [3:0] state, next_state;
    reg [5:0] step_cnt; 
    reg [4:0] cell_idx; 
    reg [2:0] row, col; 
    reg [7:0] t_tens, t_ones;
    reg [1:0] cur_cell_val;
    reg [19:0] cool_cnt; // 冷却计数器

    // 冷却时间常数：100,000 个周期在 100MHz 下等于 1ms，确保串口线绝对空闲
    localparam COOL_TIME = 20'd100_000; 

    wire [4:0] cur_place = (col - 3'd1) * 3'd5 + (row - 3'd1);

    // --- 第一段：时序逻辑 ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= next_state;
    end

    // --- 第二段：组合逻辑 (跳转决策) ---
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE:       if (start) next_state = S_PREPARE;
            S_PREPARE:    next_state = S_SET_DATA;
            S_SET_DATA:   next_state = S_SEND_TRIG;
            S_SEND_TRIG:  next_state = S_WAIT_START;
            S_WAIT_START: if (uart_tx_busy) next_state = S_WAIT_DONE; // 确认已收到
            S_WAIT_DONE:  if (!uart_tx_busy) next_state = S_COOL_DOWN; // 确认已发完
            S_COOL_DOWN: begin
                if (cool_cnt >= COOL_TIME) begin
                    if (cell_idx == 5'd25) next_state = S_DONE;
                    else                   next_state = S_SET_DATA;
                end
            end
            S_DONE:       next_state = S_IDLE;
            default:      next_state = S_IDLE;
        endcase
    end

    // --- 第三段：时序逻辑 (数据路径与输出) ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_tx_en <= 0; uart_tx_data <= 0; busy <= 0; done <= 0;
            step_cnt <= 0; cell_idx <= 0; row <= 1; col <= 1; cool_cnt <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    busy <= 0; done <= 0; step_cnt <= 0; cell_idx <= 0;
                    row <= 1; col <= 1; cool_cnt <= 0; uart_tx_en <= 0;
                end

                S_PREPARE: begin
                    busy <= 1;
                    t_tens <= cnt / 10;
                    t_ones <= cnt % 10;
                    cur_cell_val <= info_table[49 - (cur_place << 1) -: 2];
                end

                S_SET_DATA: begin
                    cool_cnt <= 0; // 重置冷却计数
                    // 如果当前单元cnt为0，跳过此单元
                    if (cur_cell_val == 2'd0) begin
                        // 直接跳到下一个单元
                        if (col == 3'd5) begin
                            col <= 3'd1;
                            row <= row + 1'b1;
                        end else begin
                            col <= col + 1'b1;
                        end
                        cell_idx <= cell_idx + 1'b1;
                    end else begin
                        case (step_cnt)
                            6'd0:  uart_tx_data <= ASCII_0 + t_tens;
                            6'd1:  uart_tx_data <= ASCII_0 + t_ones;
                            6'd2:  uart_tx_data <= ASCII_SPACE;
                            6'd3:  uart_tx_data <= ASCII_0 + row;
                            6'd4:  uart_tx_data <= ASCII_STAR;
                            6'd5:  uart_tx_data <= ASCII_0 + col;
                            6'd6:  uart_tx_data <= ASCII_STAR;
                            6'd7:  uart_tx_data <= ASCII_0 + cur_cell_val;
                            6'd8:  uart_tx_data <= ASCII_SPACE;
                            6'd9:  uart_tx_data <= ASCII_CR;
                            6'd10: uart_tx_data <= ASCII_LF;
                            default: uart_tx_data <= ASCII_SPACE;
                        endcase
                    end
                end

                S_SEND_TRIG: begin
                    uart_tx_en <= 1'b1;
                end

                S_WAIT_START, S_WAIT_DONE: begin
                    uart_tx_en <= 1'b0;
                end

                S_COOL_DOWN: begin
                    cool_cnt <= cool_cnt + 1'b1;
                    // 在冷却期间的第一个周期更新下一次要发送的内容
                    if (cool_cnt == 20'd1) begin
                        if (step_cnt < 6'd8) begin
                            step_cnt <= step_cnt + 1'b1;
                        end else if (step_cnt == 6'd8) begin
                            if (col == 3'd5) step_cnt <= 6'd9;
                            else begin
                                step_cnt <= 6'd3; // 跳过总数
                                cell_idx <= cell_idx + 1'b1;
                                col      <= col + 1'b1;
                            end
                        end else if (step_cnt == 6'd9) begin
                            step_cnt <= 6'd10;
                        end else if (step_cnt == 6'd10) begin
                            cell_idx <= cell_idx + 1'b1;
                            if (cell_idx != 5'd24) begin
                                step_cnt <= 6'd3;
                                col <= 3'd1; row <= row + 1'b1;
                            end else begin
                                cell_idx <= 5'd25; // 准备跳 DONE
                            end
                        end
                    end
                    // 在冷却快结束时提前锁存下一拍数据，保证 SET_DATA 状态数据稳定
                    if (cool_cnt == COOL_TIME - 1) begin
                        cur_cell_val <= info_table[49 - (cur_place << 1) -: 2];
                    end
                end

                S_DONE: begin
                    done <= 1'b1;
                    busy <= 1'b0;
                end
            endcase
        end
    end

endmodule