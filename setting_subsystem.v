//========================================
// 参数配置器模块 parameter_configurator
//========================================
// 功能：
// 1. 从uart_rx接收数据，解析为参数值
// 2. 支持一位数或两位数输入
// 3. 如果第一位数后0.5ms内没有新数据，则认为是一位数
// 4. 检查参数范围（5-15）
// 5. 范围检查失败则报错，等待使能消失后回到IDLE
// 6. 检查成功则输出新参数值，默认值为10

module setting_subsystem(
    input  wire         clk              ,  // 系统时钟
    input  wire         rst_n            ,  // 系统复位，低有效
    
    // UART接收接口（来自uart_rx模块）
    input  wire         uart_rx_done     ,  // UART接收完成信号
    input  wire [7:0]   uart_rx_data     ,  // UART接收到的数据
    
    // 使能信号
    input  wire         enable           ,  // 配置器使能信号
    
    // 输出接口
    output reg  [7:0]   param_value      ,  // 输出参数值
    output reg          param_error         // 参数错误标志
);

// 参数定义
parameter CLK_FREQ = 100_000_000;           // 系统时钟频率
localparam TIMEOUT_MS = 0.5;                // 0.5ms超时时间
localparam TIMEOUT_CNT = CLK_FREQ / 2_000;  // 0.5ms对应的时钟周期数 (100M / 2000)

// 状态定义
localparam IDLE  = 3'b000;
localparam WAIT_FIRST = 3'b001;
localparam WAIT_SECOND = 3'b010;
localparam CHECK = 3'b011;
localparam ERROR_STATE = 3'b100;
localparam DONE = 3'b101;

// 寄存器定义
reg [2:0]  state;
reg [2:0]  next_state;
reg [7:0]  first_digit;
reg [7:0]  second_digit;
reg [7:0]  received_value;
reg [19:0] timeout_counter;
reg        timeout_flag;
reg        has_second_digit;

//wire define
wire digit_valid;
wire range_valid;

// 判断输入是否为ASCII数字 ('0'-'9')
assign digit_valid = (uart_rx_data >= 8'h30) && (uart_rx_data <= 8'h39);

// 将ASCII数字转换为十进制数值（0-9）
wire [7:0] ascii_to_decimal;
assign ascii_to_decimal = uart_rx_data - 8'h30;

// 范围检查：5-60
assign range_valid = (received_value >= 8'd5) && (received_value <= 8'd60);

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        state <= IDLE;
    end
    else begin
        state <= next_state;
    end
end

// 次态转移逻辑
always @(*) begin
    next_state = state;
    
    case(state)
        IDLE: begin
            if(enable && uart_rx_done && digit_valid) begin
                next_state = WAIT_FIRST;
            end
        end
        
        WAIT_FIRST: begin
            if(timeout_flag) begin
                // 超时：只有一位数
                next_state = CHECK;
            end
            else if(uart_rx_done && digit_valid) begin
                // 接收到第二位数
                next_state = WAIT_SECOND;
            end
        end
        
        WAIT_SECOND: begin
            next_state = CHECK;
        end
        
        CHECK: begin
            if(range_valid) begin
                next_state = DONE;
            end
            else begin
                next_state = ERROR_STATE;
            end
        end

        DONE: begin
           if(!enable)
            next_state = IDLE;
        end
        
        ERROR_STATE: begin
            if(!enable) begin
                // 等待使能消失
                next_state = IDLE;
            end
        end
        
        default: next_state = IDLE;
    endcase
end

//=================================================
//**          输出逻辑和数据处理
//=================================================

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        param_value <= 8'd10; 
        param_error <= 1'b0;
        first_digit <= 8'h00;
        second_digit <= 8'h00;
        received_value <= 8'h00;
        timeout_counter <= 20'h00;
        timeout_flag <= 1'b0;
        has_second_digit <= 1'b0;
    end
    else begin
        // 清除错误脉冲信号
        if(state != ERROR_STATE) begin
            param_error <= 1'b0;
        end
        
        case(state)
            IDLE: begin
                timeout_counter <= 20'h00;
                timeout_flag <= 1'b0;
                has_second_digit <= 1'b0;
                
                if(enable && uart_rx_done && digit_valid) begin
                    first_digit <= ascii_to_decimal;
                end
            end
            
            WAIT_FIRST: begin
                // 超时计数器
                if(timeout_counter < TIMEOUT_CNT - 1) begin
                    timeout_counter <= timeout_counter + 1'b1;
                    timeout_flag <= 1'b0;
                end
                else begin
                    timeout_flag <= 1'b1;
                end
                
                // 接收第二位数
                if(uart_rx_done && digit_valid) begin
                    second_digit <= ascii_to_decimal;
                    has_second_digit <= 1'b1;
                    timeout_counter <= 20'h00;
                end
            end
            
            WAIT_SECOND: begin
                // 计算接收到的数值
                if(has_second_digit) begin
                    // 两位数：第一位*10 + 第二位
                    received_value <= (first_digit * 10) + second_digit;
                end
                else begin
                    // 一位数
                    received_value <= first_digit;
                end
            end
            
            CHECK: begin
                if(range_valid) begin
                    param_value <= received_value;
                end
                else begin
                    param_error <= 1'b1;
                end
            end
            
            ERROR_STATE: begin
                param_error <= 1'b1;
            end
        endcase
    end
end

endmodule