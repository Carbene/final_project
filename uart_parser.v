//==============================================================================
// UART命令解析器（健壮版）
// 需求：
// - 格式 "m,n:a1,a2,...,a(m*n)"
// - m,n 允许 1~5
// - 元素必须 0~9，超出报错
// - 元素不足自动补 0（保持初值0），不报错
// - 元素超出 m*n 时忽略后续输入，完成
// - 超时：未输入 5s 报错；开始输入后 0.5s 空闲即收尾（不足补零，已满则完成）
//==============================================================================
module uart_parser (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] rx_data,
    input  wire       rx_done,
    input  wire       parse_enable,
    input  wire [7:0] elem_min,
    input  wire [7:0] elem_max,
    output reg  [2:0] parsed_m,
    output reg  [2:0] parsed_n,
    output reg  [199:0] parsed_matrix_flat,
    output reg        parse_done,
    output reg        parse_error
);

localparam IDLE       = 3'd0;
localparam PARSE_M    = 3'd1;
localparam PARSE_N    = 3'd2;
localparam PARSE_DATA = 3'd3;
localparam DONE       = 3'd4;
localparam ERROR      = 3'd5;

// 超时参数 (50MHz时钟)
parameter IDLE_TIMEOUT_CYCLES = 32'd250_000_000;  // 按下S2后未开始输入：5秒超时
parameter GAP_TIMEOUT_CYCLES  = 32'd25_000_000;   // 输入过程中/结束后无字符：0.5秒收尾/超时

reg [2:0]  state;
reg [4:0]  elem_index;
reg [7:0]  current_num;
reg        num_started;
reg [31:0] timeout_counter;
reg        seen_activity;
reg        target_reached;

wire [4:0] target_elems = parsed_m * parsed_n; // up to 25

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
        parsed_m <= 3'd0;
        parsed_n <= 3'd0;
        parsed_matrix_flat <= 200'd0;
        parse_done <= 1'b0;
        parse_error <= 1'b0;
        elem_index <= 5'd0;
        current_num <= 8'd0;
        num_started <= 1'b0;
        timeout_counter <= 32'd0;
        seen_activity <= 1'b0;
        target_reached <= 1'b0;
    end else begin
        if (state == IDLE) begin
            parse_done  <= 1'b0;
            parse_error <= 1'b0;
        end

        case (state)
            IDLE: begin
                if (parse_enable) begin
                    state <= PARSE_M;
                    elem_index <= 5'd0;
                    current_num <= 8'd0;
                    num_started <= 1'b0;
                    parsed_matrix_flat <= 200'd0; // 预置为0，便于不足补零
                    timeout_counter <= 32'd0;
                    seen_activity <= 1'b0;
                    target_reached <= 1'b0;
                end
            end

            PARSE_M: begin
                if (!parse_enable) begin
                    state <= IDLE;
                end else if (timeout_counter >= (seen_activity ? GAP_TIMEOUT_CYCLES : IDLE_TIMEOUT_CYCLES)) begin
                    parse_error <= 1'b1;
                    state <= ERROR;
                end else if (rx_done) begin
                    timeout_counter <= 32'd0;
                    seen_activity <= 1'b1;

                    if (rx_data >= "0" && rx_data <= "9") begin
                        current_num <= current_num * 10 + (rx_data - "0");
                        num_started <= 1'b1;
                    end else if (rx_data == " " && num_started) begin//改空格
                        // m 范围 1~5
                        if (current_num >= 1 && current_num <= 5) begin
                            parsed_m <= current_num[2:0];
                            current_num <= 8'd0;
                            num_started <= 1'b0;
                            state <= PARSE_N;
                        end else begin
                            parse_error <= 1'b1;
                            state <= ERROR;
                        end
                    end else begin
                        parse_error <= 1'b1;
                        state <= ERROR;
                    end
                end else begin
                    timeout_counter <= timeout_counter + 1'b1;
                end
            end

            PARSE_N: begin
                if (!parse_enable) begin
                    state <= IDLE;
                end else if (timeout_counter >= (seen_activity ? GAP_TIMEOUT_CYCLES : IDLE_TIMEOUT_CYCLES)) begin
                    // 只完成了 m，视为错误
                    parse_error <= 1'b1;
                    state <= ERROR;
                end else if (rx_done) begin
                    timeout_counter <= 32'd0;
                    seen_activity <= 1'b1;

                    if (rx_data >= "0" && rx_data <= "9") begin
                        current_num <= current_num * 10 + (rx_data - "0");
                        num_started <= 1'b1;
                    end else if (rx_data == " " && num_started) begin //改空格
                        // n 范围 1~5
                        if (current_num >= 1 && current_num <= 5) begin
                            parsed_n <= current_num[2:0];
                            current_num <= 8'd0;
                            num_started <= 1'b0;
                            state <= PARSE_DATA;
                        end else begin
                            parse_error <= 1'b1;
                            state <= ERROR;
                        end
                    end else begin
                        parse_error <= 1'b1;
                        state <= ERROR;
                    end
                end else begin
                    timeout_counter <= timeout_counter + 1'b1;
                end
            end

            PARSE_DATA: begin
                if (!parse_enable) begin
                    state <= IDLE;
                end else if (timeout_counter >= (seen_activity ? GAP_TIMEOUT_CYCLES : IDLE_TIMEOUT_CYCLES)) begin
                    // 收尾：若正在输入最后一个数，先存入；不足的已是0
                    if (num_started && !target_reached && (elem_index < target_elems)) begin
                        parsed_matrix_flat[elem_index*8 +: 8] <= current_num;
                        elem_index <= elem_index + 1'b1;
                    end
                    parse_done <= 1'b1;
                    state <= DONE;
                    target_reached <= 1'b1;
                end else if (rx_done) begin
                    timeout_counter <= 32'd0;
                    seen_activity <= 1'b1;

                    if (target_reached) begin
                        // 已达上限，忽略后续输入
                        parse_done <= 1'b1;
                        state <= DONE;
                    end else if (rx_data >= "0" && rx_data <= "9") begin
                        // 只允许 0~9
                        if (current_num * 10 + (rx_data - "0") > 9) begin
                            parse_error <= 1'b1;
                            state <= ERROR;
                        end else begin
                            current_num <= current_num * 10 + (rx_data - "0");
                            num_started <= 1'b1;
                        end
                    end else if ((rx_data == " " || rx_data == 8'h0D || rx_data == 8'h0A) && num_started) begin
                        // 完成一个元素
                        if (elem_index < target_elems) begin
                            parsed_matrix_flat[elem_index*8 +: 8] <= current_num;
                            elem_index <= elem_index + 1'b1;
                            current_num <= 8'd0;
                            num_started <= 1'b0;

                            if (elem_index + 1 == target_elems) begin
                                parse_done <= 1'b1;
                                state <= DONE;
                                target_reached <= 1'b1;
                            end
                        end else begin
                            // 超出上限：忽略后续
                            parse_done <= 1'b1;
                            state <= DONE;
                            target_reached <= 1'b1;
                        end
                    end else if (rx_data == 8'h20) begin
                        // 忽略空格
                    end else begin
                        parse_error <= 1'b1;
                        state <= ERROR;
                    end
                end else begin
                    timeout_counter <= timeout_counter + 1'b1;
                end
            end

            DONE: begin
                if (!parse_enable) state <= IDLE;
            end

            ERROR: begin
                if (!parse_enable) state <= IDLE;
            end

            default: state <= IDLE;
        endcase
    end
end

endmodule