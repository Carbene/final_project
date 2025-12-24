module print_specified_dim_matrix(
    input  wire        clk,
    input  wire        rst_n,

    // 控制
    input  wire        start,
    output reg         busy,
    output reg         done,
    output reg         error,

    // 目标维度（1~5）
    input  wire [2:0]  dim_m,
    input  wire [2:0]  dim_n,

    // info_table: 每个位置2bit计数，高位在前，共25处
    input  wire [49:0] info_table,

    // 与 matrix_storage 对接：读控制和地址
    output reg         read_en,
    output reg  [2:0]  dimM,
    output reg  [2:0]  dimN,
    output reg  [1:0]  mat_index,
    input  wire        rd_ready,
    input  wire [199:0] rd_data_flow,

    // 连接 matrix_printer
    output reg         matrix_printer_start,
    input  wire        matrix_printer_done,
    output reg [199:0] matrix_flat,
    output wire        use_crlf,

    // UART 发送接口
    input  wire        uart_tx_busy,
    output reg         uart_tx_en,
    output reg  [7:0]  uart_tx_data
);

    // 常量
    localparam [7:0] ASCII_0  = 8'h30;
    localparam [7:0] ASCII_CR = 8'h0D;
    localparam [7:0] ASCII_LF = 8'h0A;

    assign use_crlf = 1'b1;

    // 内部寄存
    reg [3:0]  state, next_state;
    reg [1:0]  cnt_for_dim;      // 该规格矩阵数量（0/1/2）
    reg [1:0]  remain_to_print;  // 剩余需要打印的个数
    reg [7:0]  tx_buf [0:2];     // 仅发送 "<cnt>\r\n"
    reg [2:0]  tx_len;           // 实际要发的字节数
    reg [2:0]  tx_idx;           // 当前发送到第几个字节
    reg        tx_in_progress;   // 单字节发送握手
    reg        uart_tx_busy_d;   // 打拍用于边沿检测

    // 提取计数的位置: place = (m-1)*5 + (n-1)
    wire [4:0] place = (dim_m - 3'd1) * 5 + (dim_n - 3'd1);
    wire [1:0] table_cnt = info_table[49 - (place << 1) -: 2];

    // 状态定义（两段/三段式）
    localparam S_IDLE        = 4'd0;
    localparam S_CHECK       = 4'd1;
    localparam S_PREP_TXCNT  = 4'd2;
    localparam S_TXCNT       = 4'd3;
    localparam S_PREP_READ   = 4'd4;
    localparam S_READ_PULSE  = 4'd5;
    localparam S_READ_WAIT   = 4'd6;
    localparam S_START_PRINT = 4'd7;
    localparam S_WAIT_PRINT  = 4'd8;
    localparam S_DONE        = 4'd9;
    localparam S_ERROR       = 4'd10;
    // 1) 状态寄存
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
        end else begin
            state <= next_state;
        end
    end

    // 2) 下一状态组合逻辑
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE:        if (start)                            next_state = S_CHECK;
            S_CHECK:       if (table_cnt == 2'd0)               next_state = S_ERROR;
                           else                                 next_state = S_PREP_TXCNT;
            S_PREP_TXCNT:                                         next_state = S_TXCNT;
            S_TXCNT:       if (tx_idx == tx_len)                next_state = S_PREP_READ;
            S_PREP_READ:                                          next_state = S_READ_PULSE;
            S_READ_PULSE:                                         next_state = S_READ_WAIT;
            S_READ_WAIT:   if (rd_ready)                        next_state = S_START_PRINT;
            S_START_PRINT:                                        next_state = S_WAIT_PRINT;
            S_WAIT_PRINT:  if (matrix_printer_done && remain_to_print <= 1)
                                                                next_state = S_DONE;
                           else if (matrix_printer_done)        next_state = S_PREP_READ;
            S_DONE:                                               next_state = S_IDLE;
            S_ERROR:                                              next_state = S_IDLE;
            default:                                              next_state = S_IDLE;
        endcase
    end

    // 3) 时序输出与数据路径
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy  <= 1'b0;
            done  <= 1'b0;
            error <= 1'b0;
            cnt_for_dim <= 2'd0;
            remain_to_print <= 2'd0;
            read_en <= 1'b0;
            dimM <= 3'd0;
            dimN <= 3'd0;
            mat_index <= 2'd0;
            matrix_printer_start <= 1'b0;
            matrix_flat <= 200'd0;
            uart_tx_en <= 1'b0;
            uart_tx_data <= 8'd0;
            tx_idx <= 3'd0;
            tx_len <= 3'd0;
            tx_in_progress <= 1'b0;
            uart_tx_busy_d <= 1'b0;
        end else begin
            // 默认低电平/清零脉冲类信号
            done <= 1'b0;
            error <= 1'b0;
            read_en <= 1'b0;
            matrix_printer_start <= 1'b0;
            uart_tx_en <= 1'b0;

            // 打拍
            uart_tx_busy_d <= uart_tx_busy;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    tx_in_progress <= 1'b0;
                end

                S_CHECK: begin
                    busy <= 1'b1;
                    cnt_for_dim <= table_cnt;
                    remain_to_print <= table_cnt;
                end

                // 构造 "<cnt>\r\n"，并重置发送索引
                S_PREP_TXCNT: begin
                    busy <= 1'b1;
                    tx_buf[0] <= ASCII_0 + {6'd0, cnt_for_dim};
                    tx_buf[1] <= ASCII_CR;
                    tx_buf[2] <= ASCII_LF;
                    tx_len    <= 3'd3;
                    tx_idx    <= 3'd0;
                    tx_in_progress <= 1'b0;
                end

                // 逐字节发送缓冲
                S_TXCNT: begin
                    busy <= 1'b1;
                    if (tx_idx < tx_len) begin
                        // 若没有在传输中且 TX 空闲，则发起一个字节
                        if (!tx_in_progress && !uart_tx_busy) begin
                            uart_tx_data   <= tx_buf[tx_idx];
                            uart_tx_en     <= 1'b1;     // 脉冲
                            tx_in_progress <= 1'b1;     // 标记进入传输中
                        end
                        // 检测 busy 从 1 -> 0 的下降沿，认为该字节完成
                        if (tx_in_progress && uart_tx_busy_d && !uart_tx_busy) begin
                            tx_in_progress <= 1'b0;
                            tx_idx <= tx_idx + 1'b1;
                        end
                    end
                end

                // 对存储发起读取请求
                S_PREP_READ: begin
                    busy <= 1'b1;
                    dimM <= dim_m;
                    dimN <= dim_n;
                    // mat_index 在 WAIT_PRINT 中推进
                end
                S_READ_PULSE: begin
                    busy <= 1'b1;
                    read_en <= 1'b1; // 单拍脉冲
                end
                S_READ_WAIT: begin
                    busy <= 1'b1;
                    if (rd_ready) begin
                        matrix_flat <= rd_data_flow; // 锁存数据
                    end
                end
                S_START_PRINT: begin
                    busy <= 1'b1;
                    matrix_printer_start <= 1'b1; // 单拍启动
                end
                S_WAIT_PRINT: begin
                    busy <= 1'b1;
                    if (matrix_printer_done) begin
                        if (remain_to_print > 0)
                            remain_to_print <= remain_to_print - 1'b1;
                        if (remain_to_print > 1)
                            mat_index <= mat_index + 1'b1; // 下一张
                        else
                            mat_index <= 2'd0; // 复位
                    end
                end

                S_DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1; // 脉冲通知上层
                    // 其他寄存默认保持/清
                end

                S_ERROR: begin
                    busy  <= 1'b0;
                    error <= 1'b1; // 脉冲报错
                end
            endcase
        end
    end

endmodule