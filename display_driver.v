`timescale 1ns / 1ps
//======================================================================
// 模块名称：display_driver
// 功能描述：EGO1开发板数码管驱动模块
//          将两个个位数分别显示在DK1的第1、2个数码管
//          将一个十位数（0-99）显示在DK2的第7、8个数码管
// 版本信息：Verilog-2001 (兼容Icarus Verilog)
//======================================================================
module display_driver(
    input wire clk,                    // 系统时钟（50MHz）
    input wire rst_n,                  // 低电平复位信号
    input wire [3:0] dk1_data,         // 第一个个位数（0-9），显示在数码管1
    input wire [3:0] dk2_data,         // 第二个个位数（0-9），显示在数码管2
    input wire [7:0] dk7_8_data,       // 十位数，高4位=十位，低4位=个位，显示在数码管7、8
    output reg [7:0] dk1,              // 段码输出（第一组4位数码管）
    output reg [7:0] dk2,              // 段码输出（第二组4位数码管）
    output reg [3:0] dk1_digit_select, // 位选信号（第一组4位数码管，BIT1-BIT4）
    output reg [3:0] dk2_digit_select  // 位选信号（第二组4位数码管，BIT5-BIT8）
);
// 输入数据合法性限制（确保不超过9）
wire [3:0] dk1_data_valid = (dk1_data > 4'd9) ? 4'd9 : dk1_data;
wire [3:0] dk2_data_valid = (dk2_data > 4'd9) ? 4'd9 : dk2_data;
wire [3:0] dk7_8_tens    = (dk7_8_data[7:4] > 4'd9) ? 4'd9 : dk7_8_data[7:4];
wire [3:0] dk7_8_ones    = (dk7_8_data[3:0] > 4'd9) ? 4'd9 : dk7_8_data[3:0];

// ✅ 移除function，改为组合逻辑
reg [7:0] seg_code_lut;
always @(*) begin
    case (dk1_data_valid)
        4'd0: seg_code_lut = 8'h3F;  // 0011_1111
        4'd1: seg_code_lut = 8'h06;  // 0000_0110
        4'd2: seg_code_lut = 8'h5B;  // 0101_1011
        4'd3: seg_code_lut = 8'h4F;  // 0100_1111
        4'd4: seg_code_lut = 8'h66;  // 0110_0110
        4'd5: seg_code_lut = 8'h6D;  // 0110_1101
        4'd6: seg_code_lut = 8'h7D;  // 0111_1101
        4'd7: seg_code_lut = 8'h07;  // 0000_0111
        4'd8: seg_code_lut = 8'h7F;  // 0111_1111
        4'd9: seg_code_lut = 8'h6F;  // 0110_1111
        default: seg_code_lut = 8'h00;  // 默认关闭
    endcase
end

reg [7:0] seg_code_lut2;
always @(*) begin
    case (dk2_data_valid)
        4'd0: seg_code_lut2 = 8'h3F;
        4'd1: seg_code_lut2 = 8'h06;
        4'd2: seg_code_lut2 = 8'h5B;
        4'd3: seg_code_lut2 = 8'h4F;
        4'd4: seg_code_lut2 = 8'h66;
        4'd5: seg_code_lut2 = 8'h78;//T0111_1000
        4'd6: seg_code_lut2 = 8'h77;//A0111_0111
        4'd7: seg_code_lut2 = 8'h7C;//B0111_1100
        4'd8: seg_code_lut2 = 8'h39;//C0011_1001
        4'd9: seg_code_lut2 = 8'h0E;//J0000_1110
        default: seg_code_lut2 = 8'h00;
    endcase
end

reg [7:0] seg_code_tens;
always @(*) begin
    case (dk7_8_tens)
        4'd0: seg_code_tens = 8'h3F;
        4'd1: seg_code_tens = 8'h06;
        4'd2: seg_code_tens = 8'h5B;
        4'd3: seg_code_tens = 8'h4F;
        4'd4: seg_code_tens = 8'h66;
        4'd5: seg_code_tens = 8'h6D;
        4'd6: seg_code_tens = 8'h7D;
        4'd7: seg_code_tens = 8'h07;
        4'd8: seg_code_tens = 8'h7F;
        4'd9: seg_code_tens = 8'h6F;
        default: seg_code_tens = 8'h00;
    endcase
end

reg [7:0] seg_code_ones;
always @(*) begin
    case (dk7_8_ones)
        4'd0: seg_code_ones = 8'h3F;
        4'd1: seg_code_ones = 8'h06;
        4'd2: seg_code_ones = 8'h5B;
        4'd3: seg_code_ones = 8'h4F;
        4'd4: seg_code_ones = 8'h66;
        4'd5: seg_code_ones = 8'h6D;
        4'd6: seg_code_ones = 8'h7D;
        4'd7: seg_code_ones = 8'h07;
        4'd8: seg_code_ones = 8'h7F;
        4'd9: seg_code_ones = 8'h6F;
        default: seg_code_ones = 8'h00;
    endcase
end


// 扫描计数器配置
// 目标：每个数码管刷新频率约100Hz（50MHz/(62500*8)）
localparam SCAN_DIVIDER = 16'd62500;  // 分频系数

// 扫描控制信号
reg [15:0] scan_counter;              // 分频计数器
reg [2:0]  scan_position;             // 扫描位置（0~7对应8个数码管）
wire       scan_tick = (scan_counter == SCAN_DIVIDER - 1'b1);

// 分频计数器
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        scan_counter <= 16'd0;
    else if (scan_tick)
        scan_counter <= 16'd0;
    else
        scan_counter <= scan_counter + 1'b1;
end

// 扫描位置更新
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        scan_position <= 3'd0;
    else if (scan_tick)
        scan_position <= scan_position + 1'b1;
end

// 数码管扫描显示逻辑
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        dk1 <= 8'h00;
        dk2 <= 8'h00;
        dk1_digit_select <= 4'h0;
        dk2_digit_select <= 4'h0;
    end else begin
        // 默认关闭所有段码和位选
        dk1 <= 8'h00;
        dk2 <= 8'h00;
        dk1_digit_select <= 4'h0;
        dk2_digit_select <= 4'h0;
        
        // 根据扫描位置选择对应的数码管显示
        case (scan_position)
            3'd0: begin  // 数码管1（BIT1）- 显示dk1_data
                dk1 <= seg_code_lut;
                dk1_digit_select <= 4'h1;  // 0001，选通BIT1
            end
            
            3'd1: begin  // 数码管2（BIT2）- 显示dk2_data
                dk1 <= seg_code_lut2;
                dk1_digit_select <= 4'h2;  // 0010，选通BIT2
            end
            
            3'd6: begin  // 数码管7（BIT7）- 显示十位
                dk2 <= seg_code_tens;
                dk2_digit_select <= 4'h4;  // 0100，选通BIT7
            end
            
            3'd7: begin  // 数码管8（BIT8）- 显示个位
                dk2 <= seg_code_ones;
                dk2_digit_select <= 4'h8;  // 1000，选通BIT8
            end
            
            default: begin  // 其他数码管关闭
                // 保持默认关闭状态
            end
        endcase
    end
end

endmodule