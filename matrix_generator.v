module matrix_generator (
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [2:0] gen_m,
    input wire [2:0] gen_n,
    input wire [7:0] elem_min,      // 元素最小值
    input wire [7:0] elem_max,      // 元素最大值
    
    output reg [199:0] gen_matrix_flat,
    output reg gen_done
);
// 状态机定义
localparam IDLE      = 2'd0;
localparam GENERATE  = 2'd1;
localparam DONE      = 2'd2;

reg [1:0] state;
reg [2:0] i, j;

reg [15:0] lfsr;
reg [7:0] raw_val; 

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
        gen_done <= 1'b0;
        gen_matrix_flat <= 200'd0;
        i <= 3'd0;
        j <= 3'd0;
        lfsr <= 16'hACE1;
        raw_val <= 8'd0;  
    end else begin
        gen_done <= 1'b0;
    
        lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
        
        case (state)
            IDLE: begin
                if (start) begin
                    i <= 3'd0;
                    j <= 3'd0;
                    state <= GENERATE;
                end
            end

            GENERATE: begin
                begin : GEN_VAL
                    reg [7:0] v;
                    reg [5:0] idx;
                    v = {4'd0, lfsr[3:0]};
                    if (v > elem_max) v = v - (elem_max - elem_min + 1);
                    if (v < elem_min) v = elem_min;
                    if (v > 8'd9)    v = 8'd9;
                    raw_val <= v;
                    idx = (i * gen_n) + j;
                    gen_matrix_flat[idx*8 +: 8] <= v;
                end
                
                if (j == gen_n - 1) begin
                    j <= 3'd0;
                    if (i == gen_m - 1) begin
                        state <= DONE;
                    end else begin
                        i <= i + 1'b1;
                    end
                end else begin
                    j <= j + 1'b1;
                end
            end
            
            DONE: begin
                gen_done <= 1'b1;
                state <= IDLE;
            end
            
            default: state <= IDLE;
        endcase
    end
end

endmodule