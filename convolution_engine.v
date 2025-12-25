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
    
    // UART发送接口（周期数）
    output wire uart_tx_en,
    output wire [7:0] uart_tx_data,
    input uart_tx_busy
);

    // =========================================================
    // 简化设计：两阶段方案（正确性优先）
    // 阶段1 (LOAD_IMAGE): 读取全部120个像素到本地存储
    // 阶段2 (CALC_CONV):  逐个计算80个卷积结果
    // =========================================================

    // --- 状态机 ---
    localparam IDLE           = 3'd0;
    localparam RECEIVE_KERNEL = 3'd1;
    localparam LOAD_IMAGE     = 3'd2;  // 加载图像数据
    localparam CALC_CONV      = 3'd3;  // 计算卷积
    localparam PRINT_RESULT   = 3'd4;
    localparam SEND_CYCLES    = 3'd5;
    localparam DONE_STATE     = 3'd6;
    
    reg [2:0] state, next_state;

    // --- 卷积核存储 (3x3 = 9个元素) ---
    reg [3:0] kernel [0:8];
    reg [3:0] kernel_count;

    // --- 图像数据本地存储 (10x12 = 120个元素) ---
    reg [3:0] image [0:119];
    
    // --- ROM 控制接口 ---
    reg [6:0] load_addr;         // 0-119: 加载地址计数
    reg [3:0] load_row, load_col; // 行列计数器（避免除法）
    reg [3:0] rom_x, rom_y;
    wire [3:0] rom_data;
    reg [1:0] load_phase;        // 0=发地址, 1=等ROM采样, 2=收数据

    input_image_rom rom_inst (
        .clk(clk),
        .x(rom_x),
        .y(rom_y),
        .data_out(rom_data)
    );

    // --- 卷积计算控制 ---
    reg [6:0] calc_idx;          // 0-79: 当前计算的输出索引
    reg [3:0] out_row, out_col;  // 输出位置 (0-7, 0-9)
    
    // --- 结果存储 ---
    reg [15:0] conv_result [0:79];
    
    // --- 周期计数 ---
    reg [15:0] cycle_counter;
    reg [15:0] compute_cycles;

    // --- 状态转移逻辑 ---
    always @(posedge clk or posedge rst) begin
        if (rst) state <= IDLE;
        else state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            IDLE:           if (enable) next_state = RECEIVE_KERNEL;
            RECEIVE_KERNEL: if (kernel_count == 4'd9) next_state = LOAD_IMAGE;
            LOAD_IMAGE:     if (load_addr == 7'd120 && load_phase == 2'd0) next_state = CALC_CONV;
            CALC_CONV:      if (calc_idx == 7'd80) next_state = PRINT_RESULT;
            PRINT_RESULT:   if (print_done) next_state = SEND_CYCLES;
            SEND_CYCLES:    if (cycle_tx_done) next_state = DONE_STATE;
            DONE_STATE:     if (!enable) next_state = IDLE;
        endcase
    end

    // --- 接收卷积核数据 ---
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            kernel_count <= 4'd0;
        end else if (state == IDLE) begin
            kernel_count <= 4'd0;
        end else if (state == RECEIVE_KERNEL && uart_rx_valid) begin
            if (uart_rx_data >= 8'd48 && uart_rx_data <= 8'd57) begin
                kernel[kernel_count] <= uart_rx_data - 8'd48;
                kernel_count <= kernel_count + 1;
            end
        end
    end

    // --- 阶段1: 加载图像数据 ---
    // 三拍流程：发地址 -> 等ROM采样 -> 收数据
    integer i;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            load_addr <= 7'd0;
            load_row <= 4'd0;
            load_col <= 4'd0;
            load_phase <= 2'd0;
            rom_x <= 4'd0;
            rom_y <= 4'd0;
            for (i = 0; i < 120; i = i + 1) image[i] <= 4'd0;
        end else if (state == LOAD_IMAGE) begin
            case (load_phase)
                2'd0: begin
                    // 发地址阶段
                    rom_x <= load_row;
                    rom_y <= load_col;
                    load_phase <= 2'd1;
                end
                2'd1: begin
                    // 等待ROM采样地址（这一拍ROM在采样地址）
                    load_phase <= 2'd2;
                end
                2'd2: begin
                    // 收数据阶段（ROM数据现在有效）
                    image[load_addr] <= rom_data;
                    load_addr <= load_addr + 1;
                    // 更新行列计数器
                    if (load_col == 4'd11) begin
                        load_col <= 4'd0;
                        load_row <= load_row + 1;
                    end else begin
                        load_col <= load_col + 1;
                    end
                    load_phase <= 2'd0;
                end
                default: load_phase <= 2'd0;
            endcase
        end else if (state == IDLE) begin
            load_addr <= 7'd0;
            load_row <= 4'd0;
            load_col <= 4'd0;
            load_phase <= 2'd0;
        end
    end

    // --- 阶段2: 卷积计算 ---
    // 输出(out_row, out_col) 对应输入窗口 [out_row:out_row+2, out_col:out_col+2]
    
    // 使用显式位宽计算地址，避免综合问题
    wire [6:0] base_addr = {3'b0, out_row} * 7'd12 + {3'b0, out_col};
    
    wire [6:0] addr0 = base_addr;
    wire [6:0] addr1 = base_addr + 7'd1;
    wire [6:0] addr2 = base_addr + 7'd2;
    wire [6:0] addr3 = base_addr + 7'd12;
    wire [6:0] addr4 = base_addr + 7'd13;
    wire [6:0] addr5 = base_addr + 7'd14;
    wire [6:0] addr6 = base_addr + 7'd24;
    wire [6:0] addr7 = base_addr + 7'd25;
    wire [6:0] addr8 = base_addr + 7'd26;
    
    // 从本地存储读取窗口数据（组合逻辑）
    wire [3:0] p0 = image[addr0];
    wire [3:0] p1 = image[addr1];
    wire [3:0] p2 = image[addr2];
    wire [3:0] p3 = image[addr3];
    wire [3:0] p4 = image[addr4];
    wire [3:0] p5 = image[addr5];
    wire [3:0] p6 = image[addr6];
    wire [3:0] p7 = image[addr7];
    wire [3:0] p8 = image[addr8];
    
    // 卷积计算（组合逻辑）
    wire [11:0] m0 = p0 * kernel[0];
    wire [11:0] m1 = p1 * kernel[1];
    wire [11:0] m2 = p2 * kernel[2];
    wire [11:0] m3 = p3 * kernel[3];
    wire [11:0] m4 = p4 * kernel[4];
    wire [11:0] m5 = p5 * kernel[5];
    wire [11:0] m6 = p6 * kernel[6];
    wire [11:0] m7 = p7 * kernel[7];
    wire [11:0] m8 = p8 * kernel[8];
    
    wire [15:0] conv_sum = m0 + m1 + m2 + m3 + m4 + m5 + m6 + m7 + m8;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            calc_idx <= 7'd0;
            out_row <= 4'd0;
            out_col <= 4'd0;
            cycle_counter <= 16'd0;
            compute_cycles <= 16'd0;
        end else if (state == LOAD_IMAGE) begin
            // 在进入CALC_CONV前，确保计数器已重置
            if (next_state == CALC_CONV) begin
                cycle_counter <= 16'd0;
            end
        end else if (state == CALC_CONV) begin
            cycle_counter <= cycle_counter + 1;
            
            if (calc_idx < 7'd80) begin
                // 保存当前卷积结果
                conv_result[calc_idx] <= conv_sum;
                calc_idx <= calc_idx + 1;
                
                // 更新输出坐标 (行优先遍历，8行x10列)
                if (out_col == 4'd9) begin
                    out_col <= 4'd0;
                    out_row <= out_row + 1;
                end else begin
                    out_col <= out_col + 1;
                end
                
                // 记录完成时的周期数
                if (calc_idx == 7'd79) begin
                    compute_cycles <= cycle_counter;
                end
            end
        end else if (state == IDLE) begin
            calc_idx <= 7'd0;
            out_row <= 4'd0;
            out_col <= 4'd0;
            cycle_counter <= 16'd0;
            compute_cycles <= 16'd0;
        end
    end

    // --- 周期计数发送 ---
    wire cycle_tx_done;
    
    cycle_counter_tx u_cycle_tx (
        .clk(clk),
        .rst_n(~rst),
        .enable(state == SEND_CYCLES),
        .cycle_count(compute_cycles),
        .uart_tx_en(uart_tx_en),
        .uart_tx_data(uart_tx_data),
        .uart_tx_busy(uart_tx_busy),
        .done(cycle_tx_done)
    );

    // --- 矩阵数据打包与打印控制 ---
    integer j;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            print_enable <= 1'b0;
        end else if (state == PRINT_RESULT && !print_enable) begin
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