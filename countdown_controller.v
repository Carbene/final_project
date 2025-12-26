module countdown_controller(
    input wire clk,
    input wire rst_n,
    input wire start,
    output reg counting, // 倒计时进行中标志
    output reg done,     // 倒计时完成标志
    input wire end_timer,
    output reg [7:0] dk1_segments,
    output reg [3:0] dk_digit_select,
    input [7:0] countdown_time
);  
    parameter NUM_0 = 8'b0011_1111; 
    parameter NUM_1 = 8'b0000_0110; 
    parameter NUM_2 = 8'b0101_1011; 
    parameter NUM_3 = 8'b0100_1111; 
    parameter NUM_4 = 8'b0110_0110; 
    parameter NUM_5 = 8'b0110_1101; 
    parameter NUM_6 = 8'b0111_1101;
    parameter NUM_7 = 8'b0000_0111;
    parameter NUM_8 = 8'b0111_1111;
    parameter NUM_9 = 8'b0110_1111; 

    // 倒计时相关寄存器
    reg [26:0] sec_counter; // 秒计数器，100MHz时钟，1秒=100_000_000周期
    reg [5:0] countdown_value; // 倒计时值，0-60
    localparam SEC_COUNT = 27'd100_000_000; // 1秒的时钟周期数


    // 显示相关寄存器
    reg [15:0] display_counter; // 显示分频计数器，100MHz / 50000 ≈ 2kHz
    localparam DISPLAY_DIV = 16'd50000;
    reg [1:0] digit_sel; // 数码管选择：0=十位(dk1), 1=个位(dk2)
    reg [7:0] tens_seg, ones_seg; // 十位和个位的段码

    // 计算段码
    always @(*) begin
        case (countdown_value / 10)
            0: tens_seg = NUM_0;
            1: tens_seg = NUM_1;
            2: tens_seg = NUM_2;
            3: tens_seg = NUM_3;
            4: tens_seg = NUM_4;
            5: tens_seg = NUM_5;
            6: tens_seg = NUM_6;
            7: tens_seg = NUM_7;
            8: tens_seg = NUM_8;
            9: tens_seg = NUM_9;
            default: tens_seg = NUM_0;
        endcase
        case (countdown_value % 10)
            0: ones_seg = NUM_0;
            1: ones_seg = NUM_1;
            2: ones_seg = NUM_2;
            3: ones_seg = NUM_3;
            4: ones_seg = NUM_4;
            5: ones_seg = NUM_5;
            6: ones_seg = NUM_6;
            7: ones_seg = NUM_7;
            8: ones_seg = NUM_8;
            9: ones_seg = NUM_9;
            default: ones_seg = NUM_0;
        endcase
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sec_counter <= 27'd0;
            countdown_value <= countdown_time;
            counting <= 1'b0;
            done <= 1'b0;
        end else begin
            // 重置脉冲
            done <= 1'b0;

            if (start && !counting) begin
                counting <= 1'b1;
                countdown_value <= countdown_time;
                sec_counter <= 27'd0;
            end else if (counting) begin
                if (end_timer) begin
                    // 按钮按下，结束倒计时，拉高feedback一拍
                    counting <= 1'b0;
                end else if (sec_counter < SEC_COUNT - 1) begin
                    sec_counter <= sec_counter + 1;
                end else begin
                    sec_counter <= 27'd0;
                    if (countdown_value > 0) begin
                        countdown_value <= countdown_value - 1;
                    end else begin
                        // 倒计时自然结束，如果没按过按钮，拉高done一拍
                        counting <= 1'b0;
                        done <= 1'b1;
                    end
                end
            end
        end
    end

    // 数码管显示逻辑（高频交替显示十位和个位，使用公用dk1_segments）
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            display_counter <= 16'd0;
            digit_sel <= 2'd0;
            dk1_segments <= 8'd0;
            dk_digit_select <= 8'b0000_0001; // 默认选择十位
        end else begin
            if (display_counter < DISPLAY_DIV - 1) begin
                display_counter <= display_counter + 1;
            end else begin
                display_counter <= 16'd0;
                digit_sel <= digit_sel + 1'b1; // 交替选择
                if (digit_sel == 2'd0) begin
                    dk1_segments <= tens_seg;  // 显示十位
                    dk_digit_select <= 4'b1000; // 选择十位位
                end else begin
                    dk1_segments <= ones_seg;  // 显示个位
                    dk_digit_select <= 4'b0100; // 选择个位位
                end
            end
        end
    end

endmodule