module clock_divider #(
    parameter CLK_FREQ = 100_000_000,
    parameter EXPECTED_FREQ = 1
)(
    input wire clk,
    input wire rst_n,
    
    output reg tick
);
    localparam CNT   = CLK_FREQ / EXPECTED_FREQ;
    reg [31:0] cnt_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_reg <= 0;
            tick <= 0;
        end else begin
            if (cnt_reg >= CNT - 1) begin
                cnt_reg <= 0;
                tick <= 1'b1;
            end else begin
                cnt_reg <= cnt_reg + 1'b1;
                tick <= 1'b0;
            end
        end
    end

endmodule