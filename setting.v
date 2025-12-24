module setting(
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [7:0] uart_data,
    input wire uart_data_valid,
    output reg setting_done,
    output reg [3:0] setting_time
);
    // 状态定义
    localparam IDLE       = 2'd0;
    localparam RECEIVE    = 2'd1;
    localparam COMPLETE   = 2'd2;

    reg [1:0] state, next_state;

    // 状态转移
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    // 下一个状态逻辑
    always @(*) begin
        case (state)
            IDLE: begin
                if (start)
                    next_state = RECEIVE;
                else
                    next_state = IDLE;
            end
            RECEIVE: begin
                next_state = COMPLETE;
            end
            COMPLETE: begin
                next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

    // 输出逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            setting_done <= 1'b0;
            setting_time <= 4'd0;
        end else begin
            case (state)
                IDLE: begin
                    setting_done <= 1'b0;
                end
                RECEIVE: begin
                    setting_time <= uart_data[3:0]; // 只取低4位作为设置时间
                end
                COMPLETE: begin
                    setting_done <= 1'b1; // 设置完成信号拉高一拍
                end
            endcase
        end
    end

endmodule