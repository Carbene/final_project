module print_table(
    input wire clk,
    input wire rst_n,
    input wire start,         // 请确保外部已处理为单脉冲信号
    // UART TX 接口
    input wire uart_tx_busy,
    output reg uart_tx_en,
    output reg [7:0] uart_tx_data,
    // 数据输入
    input wire [49:0] info_table,
    input wire [7:0] cnt,     // 外部输入的 total_cnt
    // 状态指示
    output reg busy,
    output reg done
);

    // --- ASCII 常量定义 ---
    localparam [7:0] ASCII_STAR  = 8'h2A; // '*'
    localparam [7:0] ASCII_SPACE = 8'h20; // ' '
    localparam [7:0] ASCII_0     = 8'h30;
    localparam [7:0] ASCII_CR    = 8'h0D; // '\r'
    localparam [7:0] ASCII_LF    = 8'h0A; // '\n'

    // --- 状态机定义 ---
    localparam S_IDLE        = 4'd0,
               S_PREPARE     = 4'd1,
               S_SET_DATA    = 4'd2, // 核心：根据当前步骤准备对应的 ASCII 数据
               S_SEND_TRIG   = 4'd3, // 核心：产生一个周期的使能脉冲
               S_WAIT_ACK    = 4'd4, // 等待串口模块响应 (busy 变高)
               S_WAIT_DONE   = 4'd5, // 等待串口模块发送完成 (busy 变低)
               S_CHECK_NEXT  = 4'd6, // 判断是发下一个字符还是结束
               S_DONE        = 4'd7;

    reg [3:0] state, next_state;

    // --- 控制寄存器 ---
    reg [5:0] step_cnt; // 记录当前这一行发到第几个字符 (0-7)
    reg [4:0] cell_idx; // 记录当前发送的是 25 个单元中的第几个 (0-24)
    reg [2:0] row, col; // 矩阵行列坐标
    reg [7:0] t_tens, t_ones;
    reg [1:0] cur_cell_val;

    // 矩阵位置计算逻辑：(col-1)*5 + (row-1)
    wire [4:0] cur_place = (col - 3'd1) * 3'd5 + (row - 3'd1);

    // --- 第一段：同步时序逻辑 (状态转换) ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            state <= S_IDLE;
        else 
            state <= next_state;
    end

    // --- 第二段：组合逻辑 (次态跳转) ---
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE: begin
                if (start) next_state = S_PREPARE;
            end
            S_PREPARE: begin
                next_state = S_SET_DATA;
            end
            S_SET_DATA: begin
                next_state = S_SEND_TRIG;
            end
            S_SEND_TRIG: begin
                next_state = S_WAIT_ACK;
            end
            S_WAIT_ACK: begin
                // 必须等到 busy 拉高，证明串口模块已经捕获到了 en 和 data
                if (uart_tx_busy) 
                    next_state = S_WAIT_DONE;
            end
            S_WAIT_DONE: begin
                // 等到 busy 拉低，证明当前字符发送彻底结束
                if (!uart_tx_busy) 
                    next_state = S_CHECK_NEXT;
            end
            S_CHECK_NEXT: begin
                // 如果一行还没发完，或者总任务没完，跳回 SET_DATA
                if (cell_idx == 5'd25) 
                    next_state = S_DONE;
                else 
                    next_state = S_SET_DATA;
            end
            S_DONE: begin
                next_state = S_IDLE;
            end
            default: next_state = S_IDLE;
        endcase
    end

    // --- 第三段：同步时序逻辑 (输出及数据路径) ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_tx_en   <= 1'b0;
            uart_tx_data <= 8'h00;
            busy         <= 1'b0;
            done         <= 1'b0;
            step_cnt     <= 6'd0;
            cell_idx     <= 5'd0;
            row          <= 3'd1;
            col          <= 3'd1;
        end else begin
            case (state)
                S_IDLE: begin
                    busy     <= 1'b0;
                    done     <= 1'b0;
                    step_cnt <= 6'd0;
                    cell_idx <= 5'd0;
                    row      <= 3'd1;
                    col      <= 3'd1;
                    uart_tx_en <= 1'b0;
                end

                S_PREPARE: begin
                    busy   <= 1'b1;
                    t_tens <= cnt / 10;
                    t_ones <= cnt % 10;
                    // 在此提取第一个单元的数据
                    cur_cell_val <= info_table[49 - (cur_place << 1) -: 2];
                end

                S_SET_DATA: begin
                    // 状态机核心：根据 step_cnt 决定当前发送哪个字符
                    case (step_cnt)
                        6'd0: uart_tx_data <= ASCII_0 + t_tens;   // 1. 发送总数十位
                        6'd1: uart_tx_data <= ASCII_0 + t_ones;   // 2. 发送总数个位
                        6'd2: uart_tx_data <= ASCII_SPACE;        // 3. 空格
                        6'd3: uart_tx_data <= ASCII_0 + row;      // 4. M
                        6'd4: uart_tx_data <= ASCII_STAR;         // 5. *
                        6'd5: uart_tx_data <= ASCII_0 + col;      // 6. N
                        6'd6: uart_tx_data <= ASCII_STAR;         // 7. *
                        6'd7: uart_tx_data <= ASCII_0 + cur_cell_val; // 8. Value
                        6'd8: uart_tx_data <= ASCII_SPACE;        // 9. 间隔空格
                        6'd9: uart_tx_data <= ASCII_CR;           // 10. 回车 (如果 col=5)
                        6'd10:uart_tx_data <= ASCII_LF;           // 11. 换行 (如果 col=5)
                        default: uart_tx_data <= ASCII_SPACE;
                    endcase
                end

                S_SEND_TRIG: begin
                    uart_tx_en <= 1'b1; // 仅拉高一个周期
                end

                S_WAIT_ACK, S_WAIT_DONE: begin
                    uart_tx_en <= 1'b0; // 必须立即拉低，防止重复触发
                end

                S_CHECK_NEXT: begin
                    // 更新索引和坐标的复杂逻辑
                    if (step_cnt < 6'd8) begin
                        // 常规字符递增
                        step_cnt <= step_cnt + 1'b1;
                    end else if (step_cnt == 6'd8) begin
                        // 发完空格后判断是否需要回车换行
                        if (col == 3'd5) begin
                            step_cnt <= 6'd9; // 去发 CR
                        end else begin
                            // 没到行末，准备下一个单元
                            step_cnt <= 6'd3; // 跳过总数，直接发下一个 M*N*V
                            cell_idx <= cell_idx + 1'b1;
                            col      <= col + 1'b1;
                            // 提前锁存下一个单元数据
                            cur_cell_val <= info_table[49 - (((col) * 5 + (row - 1)) << 1) -: 2];
                        end
                    end else if (step_cnt == 6'd9) begin
                        step_cnt <= 6'd10; // 发完 CR 发 LF
                    end else if (step_cnt == 6'd10) begin
                        // 换行完成，进入下一行或结束
                        cell_idx <= cell_idx + 1'b1;
                        if (cell_idx == 5'd24) begin
                            cell_idx <= 5'd25; // 标记结束
                        end else begin
                            step_cnt <= 6'd3;
                            col <= 3'd1;
                            row <= row + 1'b1;
                            // 提前锁存下一行开头的数据
                            cur_cell_val <= info_table[49 - (((0) * 5 + (row)) << 1) -: 2];
                        end
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