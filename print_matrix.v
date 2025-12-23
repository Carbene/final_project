module print_matrix (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [199:0] data_input,
    input  wire [2:0]  width,
    input  wire [2:0]  height,
    input  wire        start,
    input  wire        uart_tx_busy, // 新增：发送端忙信号
    output reg         busy,
    output reg         done,
    output reg  [7:0]  dout,
    output reg         dout_valid
);

    // ASCII 常量
    localparam ASCII_SPACE   = 8'h20; // ' '
    localparam ASCII_CR      = 8'h0D; // '\r'
    localparam ASCII_LF      = 8'h0A; // '\n'

    // 状态机定义
    localparam S_IDLE        = 3'd0;
    localparam S_WAIT_INPUT  = 3'd1;
    localparam S_PRINT_NUM   = 3'd2;
    localparam S_PRINT_SPACE = 3'd3;
    localparam S_PRINT_CR    = 3'd4;
    localparam S_PRINT_LF    = 3'd5;
    localparam S_DONE        = 3'd6;

    reg [2:0] state, next_state;
    reg [4:0] cnt, cnt_next; // 总计数
    reg [4:0] total_cnt, total_cnt_next;     // width*height
    reg [3:0] col_cnt, col_cnt_next;
    // reg [7:0] num_buf;
    reg [2:0] next_print;

    // 状态机
    // 现态寄存器
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            cnt <= 0;
            total_cnt <= 0;
            col_cnt <= 0;
        end else begin
            state <= next_state;
            cnt <= cnt_next;
            total_cnt <= total_cnt_next;
            col_cnt <= col_cnt_next;

        end
    end

    // 次态组合逻辑
    always @(*) begin
        next_state = state;
        cnt_next = cnt;
        total_cnt_next = total_cnt;
        col_cnt_next = col_cnt;

        case (state)
            S_IDLE: begin
                if (start) begin
                    next_state = S_WAIT_INPUT;
                end
                cnt_next = 0;
                total_cnt_next = 0;
                col_cnt_next = 0;
            end
            S_WAIT_INPUT: begin
                next_state = S_PRINT_NUM;
                total_cnt_next = width * height;
                cnt_next = 0;
                col_cnt_next = 0;
            end
            S_PRINT_NUM: begin
                if (!uart_tx_busy) begin // 等待发送端空闲
                    if (cnt < total_cnt) begin
                        next_state = S_PRINT_SPACE;
                    end else begin
                        next_state = S_PRINT_CR; // 最后一个数字后进入换行流程
                    end
                end else begin
                    next_state = S_PRINT_NUM;
                end
            end
            S_PRINT_SPACE: begin
                if (!uart_tx_busy) begin
                    cnt_next = cnt + 1;
                    if (col_cnt == width - 1) begin
                        col_cnt_next = 0;
                        next_state = S_PRINT_CR;
                    end else begin
                        col_cnt_next = col_cnt + 1;
                        next_state = S_PRINT_NUM;
                    end
                end else begin
                    next_state = S_PRINT_SPACE;
                end
            end
            S_PRINT_CR: begin
                if (!uart_tx_busy) begin
                    next_state = S_PRINT_LF;
                end else begin
                    next_state = S_PRINT_CR;
                end
            end
            S_PRINT_LF: begin
                if (!uart_tx_busy) begin
                    if (cnt==total_cnt) begin
                        next_state = S_DONE;
                    end else begin
                        next_state = S_PRINT_NUM;
                    end
                end else begin
                    next_state = S_PRINT_LF;
                end
            end
            S_DONE: begin
                if (!start) next_state = S_IDLE;
            end
        endcase
    end

    // 输出组合逻辑
    reg busy_r, done_r;
    reg [7:0] dout_r;
    always @(*) begin
        busy_r = 0;
        done_r = 0;
        dout_r = 8'd0;
        case (state)
            S_IDLE: begin
                busy_r = 0;
                done_r = 0;
                dout_r = 8'd0;
            end
            S_WAIT_INPUT: begin
                busy_r = 1;
                done_r = 0;
                dout_r = 8'd0;
            end
            S_PRINT_NUM: begin
                busy_r = 1;
                done_r = 0;
                dout_r = data_input[cnt*8 +: 8] + 8'd48;//哪个高位！！！
            end
            S_PRINT_SPACE: begin
                busy_r = 1;
                done_r = 0;
                dout_r = ASCII_SPACE;
            end
            S_PRINT_CR: begin
                busy_r = 1;
                done_r = 0;
                dout_r = ASCII_CR;
            end
            S_PRINT_LF: begin
                busy_r = 1;
                done_r = 0;
                dout_r = ASCII_LF;
            end
            S_DONE: begin
                busy_r = 0;
                done_r = 1;
                dout_r = 8'd0;
            end
        endcase
    end
    reg [2:0] last_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_state <= S_IDLE;
            busy <= 0;
            done <= 0;
            dout <= 0;
            dout_valid <= 0;
        end else begin
            busy <= busy_r;
            done <= done_r;
            dout <= dout_r;
            last_state <= state;
            // dout_valid逻辑：每次进入PRINT_NUM、PRINT_SPACE、PRINT_CR、PRINT_LF状态时拉高1拍
            if ((state == S_PRINT_NUM || state == S_PRINT_SPACE || state == S_PRINT_CR || state == S_PRINT_LF) 
                && (last_state != state)) begin
                dout_valid <= 1'b1;
            end else begin
                dout_valid <= 1'b0;
            end
        end
    end

    // 状态转移（已合并到主状态机，避免重复）

endmodule