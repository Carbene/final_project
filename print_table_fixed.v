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
    localparam S_IDLE           = 4'd0,
               S_HEADER_PREP    = 4'd1,  // 准备表头数据（BCD转换）
               S_HEADER_SET     = 4'd2,  // 设置表头字节
               S_HEADER_TRIG    = 4'd3,  // 触发发送表头
               S_HEADER_WAIT    = 4'd4,  // 等待表头发送完成
               S_HEADER_COOL    = 4'd5,  // 表头冷却
               S_HEADER_NEXT    = 4'd6,  // 表头下一字节
               S_FETCH          = 4'd7,  // 读取单元格 2-bit 计数
               S_CHECK          = 4'd8,  // 检查是否为 0
               S_SET_DATA       = 4'd9,  // 准备单元格 ASCII
               S_SEND_TRIG      = 4'd10, 
               S_WAIT_BUSY      = 4'd11, // 等待发送开始
               S_WAIT_DONE      = 4'd12, // 等待发送完成
               S_COOL_DOWN      = 4'd13, 
               S_NEXT_STEP      = 4'd14, // 推进单元和行列
               S_DONE           = 4'd15;

    reg [3:0] state, next_state;
    reg [2:0] step_cnt;       // 单元格输出步骤：0=row, 1=*, 2=col, 3=*, 4=count, 5=space
    reg [4:0] cell_idx; 
    reg [2:0] row, col; 
    reg [7:0] t_tens, t_ones;
    reg [1:0] cur_cell_val;
    reg [19:0] cool_cnt;
    reg [1:0] header_idx;     // 表头输出索引：0=tens, 1=ones, 2=space

    localparam COOL_TIME = 20'd100_000; 

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
            S_IDLE:         if (start) next_state = S_HEADER_PREP;
            
            // === 表头输出状态（独立，仅执行一次）===
            S_HEADER_PREP:  next_state = S_HEADER_SET;
            S_HEADER_SET:   next_state = S_HEADER_TRIG;
            S_HEADER_TRIG:  next_state = S_HEADER_WAIT;
            S_HEADER_WAIT:  if (!uart_tx_busy) next_state = S_HEADER_COOL;
            S_HEADER_COOL:  if (cool_cnt >= COOL_TIME) next_state = S_HEADER_NEXT;
            S_HEADER_NEXT: begin
                if (header_idx < 2'd2)
                    next_state = S_HEADER_SET;  // 继续发送下一个表头字节
                else
                    next_state = S_FETCH;       // 表头完成，进入单元格遍历
            end
            
            // === 单元格遍历状态 ===
            S_FETCH:        next_state = S_CHECK;
            S_CHECK: begin
                if (cur_cell_val == 2'd0) next_state = S_NEXT_STEP; // 计数为0直接跳过
                else                      next_state = S_SET_DATA;
            end
            S_SET_DATA:     next_state = S_SEND_TRIG;
            S_SEND_TRIG:    next_state = S_WAIT_BUSY;
            S_WAIT_BUSY:    if (uart_tx_busy) next_state = S_WAIT_DONE;
            S_WAIT_DONE:    if (!uart_tx_busy) next_state = S_COOL_DOWN;
            S_COOL_DOWN:    if (cool_cnt >= COOL_TIME) next_state = S_NEXT_STEP;
            S_NEXT_STEP: begin
                // 当前单元（非0且未全输出）需要继续输出（追加空格作为第6个字符）
                if (cur_cell_val != 2'd0 && step_cnt < 3'd5) next_state = S_SET_DATA;
                // 已处理完25个单元（cell_idx已达24），进入完成
                else if (cell_idx >= 5'd24) next_state = S_DONE;
                // 否则准备读取下一个单元
                else next_state = S_FETCH;
            end
            S_DONE:         next_state = S_IDLE;
            default:        next_state = S_IDLE;
        endcase
    end

    // --- 第三段：时序逻辑和数据 ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_tx_en <= 0; uart_tx_data <= 0; busy <= 0; done <= 0;
            step_cnt <= 0; cell_idx <= 0; row <= 1; col <= 1; cool_cnt <= 0;
            header_idx <= 0; t_tens <= 0; t_ones <= 0; cur_cell_val <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    busy <= 0; done <= 0; step_cnt <= 0; cell_idx <= 0;
                    row <= 1; col <= 1; cool_cnt <= 0; uart_tx_en <= 0;
                    header_idx <= 0;
                end

                // === 表头输出 ===
                S_HEADER_PREP: begin
                    busy <= 1;
                    header_idx <= 0;
                    // BCD 转换
                    t_tens <= (cnt >= 90) ? 8'd9 : (cnt >= 80) ? 8'd8 : (cnt >= 70) ? 8'd7 : 
                              (cnt >= 60) ? 8'd6 : (cnt >= 50) ? 8'd5 : (cnt >= 40) ? 8'd4 : 
                              (cnt >= 30) ? 8'd3 : (cnt >= 20) ? 8'd2 : (cnt >= 10) ? 8'd1 : 8'd0;
                    t_ones <= cnt % 10;
                end

                S_HEADER_SET: begin
                    case (header_idx)
                        2'd0: uart_tx_data <= ASCII_0 + t_tens;  // 十位
                        2'd1: uart_tx_data <= ASCII_0 + t_ones;  // 个位
                        2'd2: uart_tx_data <= ASCII_SPACE;       // 空格
                        default: uart_tx_data <= ASCII_SPACE;
                    endcase
                end

                S_HEADER_TRIG: begin
                    uart_tx_en <= 1'b1;
                end

                S_HEADER_WAIT: begin
                    uart_tx_en <= 1'b0;
                    cool_cnt <= 0;
                end

                S_HEADER_COOL: begin
                    cool_cnt <= cool_cnt + 1'b1;
                end

                S_HEADER_NEXT: begin
                    cool_cnt <= 0;
                    if (header_idx < 2'd2)
                        header_idx <= header_idx + 1'b1;
                    // 表头完成后，单元格从 step_cnt=0 开始
                end

                // === 单元格遍历 ===
                S_FETCH: begin
                    busy <= 1;
                    step_cnt <= 0;  // 每个新单元格从 step 0 开始
                    if (cell_idx < 5'd25) begin
                        cur_cell_val <= info_table[bit_pos +: 2];
                    end
                end

                S_SET_DATA: begin
                    // 输出格式：row * col * count（先行后列）
                    case (step_cnt)
                        3'd0: uart_tx_data <= ASCII_0 + row;       // 行号
                        3'd1: uart_tx_data <= ASCII_STAR;          // *
                        3'd2: uart_tx_data <= ASCII_0 + col;       // 列号
                        3'd3: uart_tx_data <= ASCII_STAR;          // *
                        3'd4: uart_tx_data <= ASCII_0 + {6'd0, cur_cell_val}; // 计数
                        3'd5: uart_tx_data <= ASCII_SPACE;         // 空格分隔
                        default: uart_tx_data <= ASCII_SPACE;
                    endcase
                end

                S_SEND_TRIG: uart_tx_en <= 1'b1;
                
                S_WAIT_BUSY: begin
                    if (uart_tx_busy) uart_tx_en <= 1'b0;
                    cool_cnt <= 0;
                end

                S_WAIT_DONE: begin
                    // 等待发送完成
                end

                S_COOL_DOWN: cool_cnt <= cool_cnt + 1'b1;

                S_NEXT_STEP: begin
                    cool_cnt <= 0;
                    // 当前单元还需要输出更多字符
                    if (cur_cell_val != 2'd0 && step_cnt < 3'd5) begin
                        step_cnt <= step_cnt + 1'b1;
                    end else if (cell_idx >= 5'd24) begin
                        // 已到第25个单元，停止
                    end else begin
                        // 转移到下一个单元
                        cell_idx <= cell_idx + 1'b1;
                        if (col < 3'd5) begin
                            col <= col + 1'b1;
                        end else begin
                            col <= 3'd1;
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
