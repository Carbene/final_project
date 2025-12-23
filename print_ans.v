module print_ans (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [399:0] data_input, // 400位输入
    input  wire [2:0]  width,
    input  wire [2:0]  height,
    input  wire        start,
    output reg         busy,
    output reg         done,
    output reg  [7:0]  dout
);
    // ASCII 常量
    localparam ASCII_TAB     = 8'h09; // '\t'
    localparam ASCII_CR      = 8'h0D; // '\r'
    localparam ASCII_LF      = 8'h0A; // '\n'

    // 状态机定义
    localparam S_IDLE        = 3'd0;
    localparam S_WAIT_INPUT  = 3'd1;
    localparam S_PRINT_NUM   = 3'd2;
    localparam S_PRINT_TAB   = 3'd3;
    localparam S_PRINT_CR    = 3'd4;
    localparam S_PRINT_LF    = 3'd5;
    localparam S_DONE        = 3'd6;

    reg [2:0] state, next_state;
    reg [7:0] cnt, cnt_next; // 总计数
    reg [7:0] total_cnt, total_cnt_next;     // width*height
    reg [3:0] col_cnt, col_cnt_next, row_cnt, row_cnt_next;
    reg [15:0] num_buf; // 存储当前16位数字
    reg [1:0] digit_idx, digit_idx_next; // 当前输出的数字位数索引
    reg [15:0] num_tmp, num_tmp_next;    // 当前待输出的数字副本

    //output
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
                // 输出当前最低位
                dout_r = (num_tmp % 10) + 8'd48;
            end
            S_PRINT_TAB: begin
                busy_r = 1;
                done_r = 0;
                dout_r = ASCII_TAB;
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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 0;
            done <= 0;
            dout <= 0;
            digit_idx <= 0;
            num_tmp <= 0;
        end else begin
            busy <= busy_r;
            done <= done_r;
            dout <= dout_r;
            if (state == S_WAIT_INPUT) begin
                digit_idx <= 0;
                num_tmp <= 0;
            end else if (state == S_PRINT_NUM) begin
                if (num_tmp >= 10) begin
                    num_tmp <= num_tmp / 10;
                    digit_idx <= digit_idx + 1;
                end else begin
                    digit_idx <= 0;
                    num_tmp <= 0;
                end
            end else if (state == S_PRINT_TAB || state == S_PRINT_CR || state == S_PRINT_LF || state == S_DONE) begin
                digit_idx <= 0;
                num_tmp <= 0;
            end
        end
    end

    always @(*) begin
        next_state = state;
        cnt_next = cnt;
        total_cnt_next = total_cnt;
        col_cnt_next = col_cnt;
        row_cnt_next = row_cnt;
        case (state)
            S_IDLE: begin
                if (start) begin
                    next_state = S_WAIT_INPUT;
                end
                cnt_next = 0;
                total_cnt_next = 0;
                col_cnt_next = 0;
                row_cnt_next = 0;
            end
            S_WAIT_INPUT: begin
                next_state = S_PRINT_NUM;
                total_cnt_next = width * height;
                cnt_next = 0;
                col_cnt_next = 0;
                row_cnt_next = 0;
                // 初始化num_tmp为当前数字
                num_buf = data_input[0 +: 16];
            end
            S_PRINT_NUM: begin
                if (digit_idx == 0) begin
                    // 第一次进入，装载当前数字
                    num_buf = data_input[cnt*16 +: 16];
                    num_tmp_next = num_buf;
                end
                if (num_tmp >= 10) begin
                    next_state = S_PRINT_NUM; // 继续输出下一位
                end else begin
                    if (cnt < total_cnt) begin
                        next_state = S_PRINT_TAB;
                    end else begin
                        next_state = S_PRINT_CR; // 最后一个数字后进入换行流程
                    end
                end
            end
            S_PRINT_TAB: begin
                cnt_next = cnt + 1;
                if (col_cnt == width - 1) begin
                    col_cnt_next = 0;
                    row_cnt_next = row_cnt + 1;//可能的有误，不过想想next下周期才赋值给row_cnt
                    next_state = S_PRINT_CR;
                end else begin
                    col_cnt_next = col_cnt + 1;
                    next_state = S_PRINT_NUM;
                end
            end
            S_PRINT_CR: begin
                next_state = S_PRINT_LF;
            end
            S_PRINT_LF: begin
                if (row_cnt == height) begin
                    next_state = S_DONE;
                end else begin
                    next_state = S_PRINT_NUM;
                end
            end
            S_DONE: begin
                if (!start) next_state = S_IDLE;
            end
        endcase
    end
endmodule