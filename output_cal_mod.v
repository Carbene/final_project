module output_cal_mod (
    input wire clk,
    input wire rst_n,
    input wire [2:0] op_code,
    output reg [7:0] dk2_segments,
    output reg [3:0] dk2_sel    //后四位
);
    parameter CHAR_t    = 8'b0001_1110;  // t 
    parameter CHAR_A    = 8'b1110_1110;  // A 
    parameter CHAR_B    = 8'b0011_1110;  // b 
    parameter CHAR_C    = 8'b1001_1100;  // C 
    parameter CHAR_J    = 8'b0111_1000;  // J 
    parameter CHAR_E    = 8'b1001_1110;  // E 
    parameter CHAR_NULL = 8'b0000_0000; // 空白

    always @(*) begin
        case(op_code)
            3'd0: begin
                dk2_segments = CHAR_t; //转置
                dk2_sel = 4'b0001;
            end
            3'd1: begin
                dk2_segments = CHAR_A; //加法
                dk2_sel = 4'b0001;
            end
            3'd2: begin
                dk2_segments = CHAR_B; //标量
                dk2_sel = 4'b0001;
            end
            3'd3: begin
                dk2_segments = CHAR_C; //乘法
                dk2_sel = 4'b0001;
            end
            default: begin
                dk2_segments = CHAR_NULL; //空白
                dk2_sel = 4'b0000;
            end
        endcase
    end
endmodule