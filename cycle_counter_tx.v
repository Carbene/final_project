module cycle_counter_tx (
    input clk,
    input rst_n,
    input enable,           // 开始发送周期数的触发信号
    input [15:0] cycle_count, // 周期数值
    
    output reg uart_tx_en,
    output reg [7:0] uart_tx_data,
    input uart_tx_busy,
    
    output reg done         // 发送完成标志
);

    // --- 状态定义 ---
    localparam IDLE      = 2'd0;  // 空闲，等待enable拉高
    localparam SEND_CHAR = 2'd1;  // 等待UART空闲并发送当前字符
    localparam DONE_HOLD = 2'd2;  // 已发送完，等待enable拉低后回到IDLE
    
    reg [1:0] state;
    reg [15:0] cycle_snapshot;

    // --- 字符发送序列管理 ---
    localparam SEQ_LT   = 0;
    localparam SEQ_D100 = 1;
    localparam SEQ_D10  = 2;
    localparam SEQ_D1   = 3;
    localparam SEQ_GT   = 4;
    localparam SEQ_CR   = 5;
    localparam SEQ_LF   = 6;
    localparam SEQ_DONE = 7;
    
    reg [2:0] seq_index;    // 序列索引
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_tx_en      <= 1'b0;
            uart_tx_data    <= 8'd0;
            done            <= 1'b0;
            seq_index       <= 3'd0;
            cycle_snapshot  <= 16'd0;
            state           <= IDLE;
        end else begin
            // 默认不发脉冲
            uart_tx_en <= 1'b0;

            case (state)
                IDLE: begin
                    done      <= 1'b0;
                    seq_index <= 3'd0;
                    if (enable) begin
                        cycle_snapshot <= cycle_count; // 抓拍周期数
                        state          <= SEND_CHAR;
                    end
                end

                SEND_CHAR: begin
                    if (!uart_tx_busy) begin
                        case (seq_index)
                            SEQ_LT: begin
                                uart_tx_en   <= 1'b1;
                                uart_tx_data <= 8'd60;  // '<'
                                seq_index    <= seq_index + 1;
                            end
                            SEQ_D100: begin
                                uart_tx_en   <= 1'b1;
                                uart_tx_data <= 8'd48 + (cycle_snapshot / 100) % 10;
                                seq_index    <= seq_index + 1;
                            end
                            SEQ_D10: begin
                                uart_tx_en   <= 1'b1;
                                uart_tx_data <= 8'd48 + (cycle_snapshot / 10) % 10;
                                seq_index    <= seq_index + 1;
                            end
                            SEQ_D1: begin
                                uart_tx_en   <= 1'b1;
                                uart_tx_data <= 8'd48 + cycle_snapshot % 10;
                                seq_index    <= seq_index + 1;
                            end
                            SEQ_GT: begin
                                uart_tx_en   <= 1'b1;
                                uart_tx_data <= 8'd62;  // '>'
                                seq_index    <= seq_index + 1;
                            end
                            SEQ_CR: begin
                                uart_tx_en   <= 1'b1;
                                uart_tx_data <= 8'd13;  // '\r'
                                seq_index    <= seq_index + 1;
                            end
                            SEQ_LF: begin
                                uart_tx_en   <= 1'b1;
                                uart_tx_data <= 8'd10;  // '\n'
                                seq_index    <= seq_index + 1;
                            end
                            SEQ_DONE: begin
                                done   <= 1'b1;
                                state  <= DONE_HOLD; // 等待使能拉低
                            end
                            default: seq_index <= 3'd0;
                        endcase
                    end
                end

                DONE_HOLD: begin
                    // 防止enable保持为高时重复触发
                    if (!enable) begin
                        done  <= 1'b0;
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
