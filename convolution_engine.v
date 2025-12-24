module convolution_engine (
    input clk,
    input rst,
    input enable,
    
    // UART接收接口（直接从uart_rx获取卷积核数据）
    input uart_rx_valid,
    input [7:0] uart_rx_data,
    
    // 输出接口
    output reg done,
    output reg busy,
    
    // 打印接口
    output reg print_enable,
    output reg [1279:0] matrix_data, 
    input print_done,
    
    // UART发送接口
    output reg uart_tx_valid,
    output reg [7:0] uart_tx_data,
    input uart_tx_ready
);

    // --- 状态机 ---
    localparam IDLE           = 3'd0;
    localparam RECEIVE_KERNEL = 3'd1;
    localparam COMPUTE        = 3'd2; // 流水线计算状态
    localparam PRINT_RESULT   = 3'd3;
    localparam SEND_CYCLES    = 3'd4;
    localparam DONE_STATE     = 3'd5;
    
    reg [2:0] state, next_state;

    // --- 卷积核存储 ---
    reg [3:0] kernel [0:8];
    reg [3:0] kernel_count;

    // --- ROM 控制接口 ---
    reg [3:0] rom_x, rom_x_d1;
    reg [3:0] rom_y, rom_y_d1;
    wire [3:0] rom_data;

    input_image_rom rom_inst (
        .clk(clk),
        .x(rom_x),
        .y(rom_y),
        .data_out(rom_data)
    );

    // --- 行缓存（3行缓存实现滑动窗口）---
    // 存储最近3行数据，每行12个像素
    reg [3:0] line_buf_0 [0:11];  // 最旧的行
    reg [3:0] line_buf_1 [0:11];  // 中间行
    reg [3:0] line_buf_2 [0:11];  // 最新的行（当前正在填充）
    
    // --- 3x3滑动窗口寄存器 ---
    // 布局：win[0] win[1] win[2]   对应输入矩阵的
    //       win[3] win[4] win[5]   [row-2:row, col-2:col]
    //       win[6] win[7] win[8]
    reg [3:0] win [0:8];

    // --- 计算控制信号 ---
    reg [6:0] pixel_cnt;        // 0-119: 已读取的像素计数
    reg [3:0] current_row;      // 0-9: 当前读取的行
    reg [3:0] current_col;      // 0-11: 当前读取的列
    reg [6:0] output_cnt;       // 0-79: 已输出的卷积结果计数
    reg [15:0] conv_result [0:79];
    reg [15:0] cycle_counter;

    // --- 并行MAC计算树（组合逻辑，单周期完成）---
    wire [11:0] mul [0:8];
    generate
        genvar m;
        for (m = 0; m < 9; m = m + 1) begin : mul_gen
            assign mul[m] = win[m] * kernel[m];
        end
    endgenerate
    
    // 三级加法树：第一级(3组)→第二级(2组)→第三级(1组)
    wire [12:0] add_stage1_0 = mul[0] + mul[1] + mul[2];
    wire [12:0] add_stage1_1 = mul[3] + mul[4] + mul[5];
    wire [12:0] add_stage1_2 = mul[6] + mul[7] + mul[8];
    wire [14:0] add_stage2_0 = add_stage1_0 + add_stage1_1;
    wire [15:0] conv_output  = add_stage2_0 + add_stage1_2;

    // --- 状态转移逻辑 ---
    always @(posedge clk or posedge rst) begin
        if (rst) state <= IDLE;
        else state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            IDLE:           if (enable) next_state = RECEIVE_KERNEL;
            RECEIVE_KERNEL: if (kernel_count == 4'd9) next_state = COMPUTE;
            COMPUTE:        if (output_cnt == 7'd80) next_state = PRINT_RESULT;
            PRINT_RESULT:   if (print_done) next_state = SEND_CYCLES;
            SEND_CYCLES:    if (uart_send_state == UART_IDLE && !uart_tx_valid) next_state = DONE_STATE;
            DONE_STATE:     if (!enable) next_state = IDLE;
        endcase
    end

    // --- 接收卷积核数据（从UART，自动过滤空格）---
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            kernel_count <= 4'd0;
        end else if (state == IDLE) begin
            kernel_count <= 4'd0;
        end else if (state == RECEIVE_KERNEL && uart_rx_valid) begin
            // 过滤空格（ASCII 32）和其他非数字字符
            // 只接受'0'-'9'（ASCII 48-57）
            if (uart_rx_data >= 8'd48 && uart_rx_data <= 8'd57) begin
                // 将ASCII字符转换为数值：'0'(48) -> 0, '9'(57) -> 9
                kernel[kernel_count] <= uart_rx_data - 8'd48;
                kernel_count <= kernel_count + 1;
            end
            // 忽略空格和其他字符
        end
    end

    // --- 高效流水线卷积计算 ---
    integer i;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pixel_cnt <= 7'd0;
            output_cnt <= 7'd0;
            current_row <= 4'd0;
            current_col <= 4'd0;
            cycle_counter <= 16'd0;
            rom_x <= 4'd0;
            rom_y <= 4'd0;
            rom_x_d1 <= 4'd0;
            rom_y_d1 <= 4'd0;
            
            for (i = 0; i < 9; i = i + 1) win[i] <= 4'd0;
            for (i = 0; i < 12; i = i + 1) begin
                line_buf_0[i] <= 4'd0;
                line_buf_1[i] <= 4'd0;
                line_buf_2[i] <= 4'd0;
            end
            
        end else if (state == COMPUTE) begin
            cycle_counter <= cycle_counter + 1;
            
            // ===== 阶段1：ROM地址生成（行扫描顺序）=====
            if (pixel_cnt < 7'd120) begin
                rom_x <= current_row;
                rom_y <= current_col;
                pixel_cnt <= pixel_cnt + 1;
                
                // 更新坐标
                if (current_col == 4'd11) begin
                    current_col <= 4'd0;
                    current_row <= current_row + 1;
                end else begin
                    current_col <= current_col + 1;
                end
            end
            
            // 延迟寄存器（匹配ROM 1周期延迟）
            rom_x_d1 <= rom_x;
            rom_y_d1 <= rom_y;
            
            // ===== 阶段2：接收ROM数据，更新行缓存和滑动窗口 =====
            if (pixel_cnt >= 7'd1) begin  // ROM数据延迟1周期后有效
                
                // 步骤1：将新数据写入第3行缓存
                line_buf_2[rom_y_d1] <= rom_data;
                
                // 步骤2：如果完成一行，将行缓存整体移位
                if (rom_y_d1 == 4'd11) begin
                    // 丢弃最旧的行，整体上移
                    for (i = 0; i < 12; i = i + 1) begin
                        line_buf_0[i] <= line_buf_1[i];
                        line_buf_1[i] <= line_buf_2[i];
                    end
                end
                
                // 步骤3：更新3x3滑动窗口（列方向滑动）
                // 窗口布局：[行-2,列-2] [行-2,列-1] [行-2,列]
                //           [行-1,列-2] [行-1,列-1] [行-1,列]
                //           [行,列-2]   [行,列-1]   [行,列]
                
                if (rom_y_d1 >= 4'd2) begin
                    // 窗口列方向滑动：左移一列，右侧填充新列
                    win[0] <= win[1];  win[1] <= win[2];  win[2] <= line_buf_0[rom_y_d1];
                    win[3] <= win[4];  win[4] <= win[5];  win[5] <= line_buf_1[rom_y_d1];
                    win[6] <= win[7];  win[7] <= win[8];  win[8] <= rom_data;
                end else begin
                    // 前两列：直接从缓存填充整个窗口
                    win[0] <= line_buf_0[rom_y_d1];
                    win[1] <= (rom_y_d1 >= 4'd1) ? line_buf_0[rom_y_d1-1] : 4'd0;
                    win[2] <= (rom_y_d1 >= 4'd2) ? line_buf_0[rom_y_d1-2] : 4'd0;
                    
                    win[3] <= line_buf_1[rom_y_d1];
                    win[4] <= (rom_y_d1 >= 4'd1) ? line_buf_1[rom_y_d1-1] : 4'd0;
                    win[5] <= (rom_y_d1 >= 4'd2) ? line_buf_1[rom_y_d1-2] : 4'd0;
                    
                    win[6] <= rom_data;
                    win[7] <= (rom_y_d1 >= 4'd1) ? line_buf_2[rom_y_d1-1] : 4'd0;
                    win[8] <= (rom_y_d1 >= 4'd2) ? line_buf_2[rom_y_d1-2] : 4'd0;
                end
                
                // 步骤4：当窗口有效时（行>=2, 列>=2），保存卷积结果
                if (rom_x_d1 >= 4'd2 && rom_y_d1 >= 4'd2) begin
                    conv_result[output_cnt] <= conv_output;
                    output_cnt <= output_cnt + 1;
                end
            end
            
        end else begin
            // 非COMPUTE状态，重置所有计数器
            pixel_cnt <= 7'd0;
            output_cnt <= 7'd0;
            current_row <= 4'd0;
            current_col <= 4'd0;
            cycle_counter <= 16'd0;
            rom_x <= 4'd0;
            rom_y <= 4'd0;
        end
    end

    // --- UART发送周期数（BCD格式：<cnt>\r\n）---
    localparam UART_IDLE = 3'd0;
    localparam UART_LT   = 3'd1;  // '<'
    localparam UART_D100 = 3'd2;  // 百位
    localparam UART_D10  = 3'd3;  // 十位
    localparam UART_D1   = 3'd4;  // 个位
    localparam UART_GT   = 3'd5;  // '>'
    localparam UART_CR   = 3'd6;  // '\r'
    localparam UART_LF   = 3'd7;  // '\n'
    
    reg [2:0] uart_send_state;
    reg [15:0] cycles_snapshot;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            uart_send_state <= UART_IDLE;
            uart_tx_valid <= 1'b0;
            uart_tx_data <= 8'd0;
            cycles_snapshot <= 16'd0;
        end else begin
            case (uart_send_state)
                UART_IDLE: begin
                    uart_tx_valid <= 1'b0;
                    if (state == SEND_CYCLES) begin
                        cycles_snapshot <= cycle_counter;
                        uart_send_state <= UART_LT;
                    end
                end
                
                UART_LT: begin
                    uart_tx_valid <= 1'b1;
                    uart_tx_data <= 8'd60;  // '<'
                    if (uart_tx_ready) uart_send_state <= UART_D100;
                end
                
                UART_D100: begin
                    uart_tx_data <= 8'd48 + (cycles_snapshot / 100) % 10;
                    if (uart_tx_ready) uart_send_state <= UART_D10;
                end
                
                UART_D10: begin
                    uart_tx_data <= 8'd48 + (cycles_snapshot / 10) % 10;
                    if (uart_tx_ready) uart_send_state <= UART_D1;
                end
                
                UART_D1: begin
                    uart_tx_data <= 8'd48 + cycles_snapshot % 10;
                    if (uart_tx_ready) uart_send_state <= UART_GT;
                end
                
                UART_GT: begin
                    uart_tx_data <= 8'd62;  // '>'
                    if (uart_tx_ready) uart_send_state <= UART_CR;
                end
                
                UART_CR: begin
                    uart_tx_data <= 8'd13;  // '\r'
                    if (uart_tx_ready) uart_send_state <= UART_LF;
                end
                
                UART_LF: begin
                    uart_tx_data <= 8'd10;  // '\n'
                    if (uart_tx_ready) begin
                        uart_tx_valid <= 1'b0;
                        uart_send_state <= UART_IDLE;
                    end
                end
                
                default: uart_send_state <= UART_IDLE;
            endcase
        end
    end

    // --- 矩阵数据打包与打印控制 ---
    integer j;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            print_enable <= 1'b0;
        end else if (state == PRINT_RESULT && !print_enable) begin
            // 将80个结果打包到1280位数据总线
            for (j = 0; j < 80; j = j + 1) begin
                matrix_data[j*16 +: 16] <= conv_result[j];
            end
            print_enable <= 1'b1;
        end else if (state != PRINT_RESULT) begin
            print_enable <= 1'b0;
        end
    end

    // --- 状态输出信号 ---
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            busy <= 1'b0;
            done <= 1'b0;
        end else begin
            busy <= (state != IDLE && state != DONE_STATE);
            done <= (state == DONE_STATE);
        end
    end

endmodule