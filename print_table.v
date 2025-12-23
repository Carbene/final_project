module print_table(
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire tx_busy,
    input wire [49:0] info_table,
    output reg busy,
    output reg done,
    output reg [7:0] dout,
    output reg dout_valid
);
    // ASCII码常量定义
    localparam [7:0] ASCII_STAR  = 8'h2A; // '*'
    localparam [7:0] ASCII_SPACE = 8'h20; // ' '
    localparam [7:0] ASCII_0     = 8'h30;
    localparam [7:0] ASCII_1     = 8'h31;
    localparam [7:0] ASCII_2     = 8'h32;
    localparam [7:0] ASCII_3     = 8'h33;
    localparam [7:0] ASCII_4     = 8'h34;
    localparam [7:0] ASCII_5     = 8'h35;
    localparam [7:0] ASCII_6     = 8'h36;
    localparam [7:0] ASCII_7     = 8'h37;
    localparam [7:0] ASCII_8     = 8'h38;
    localparam [7:0] ASCII_9     = 8'h39;

    // 状态机定义
    localparam S_IDLE    = 4'd0;
    localparam S_COUNT   = 4'd1;
    localparam S_GET_DIM= 4'd2;
    localparam S_PRINT_NUM   = 4'd3;
    localparam S_PRINT_STAR  = 4'd4;
    localparam S_PRINT_SPACE = 4'd5;
    localparam S_DONE    = 4'd6;
    // 后续可扩展更多状态

    reg [3:0] state, next_state;
    reg [5:0] total_count; // 最大25组，每组2位，最大和50
    reg [4:0] idx; // 计数器，最大25
    reg [1:0] count; // 当前两位count
    reg [2:0] m, n; // 当前矩阵维度

    // 状态转移
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
        end else begin
            state <= next_state;
        end
    end

    // 状态机主逻辑
    always @(*) begin
        case (state)
            S_IDLE: begin
                if (start)
                    next_state = S_COUNT;
                else
                    next_state = S_IDLE;
            end
            S_COUNT: begin
                if (idx == 25)
                    next_state = S_PRINT;
                else
                    next_state = S_COUNT;
            end
            S_TRAVERSE: begin
                if (idx == 25)
                    next_state = S_IDLE; // 可扩展done
                else
                    next_state = S_TRAVERSE;
            end

            default: next_state = S_IDLE;
        endcase
    end

    // 计数求和及维度遍历过程
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idx <= 0;
            total_count <= 0;
            busy <= 0;
            done <= 0;
            m <= 0;
            n <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    idx <= 0;
                    total_count <= 0;
                    busy <= 0;
                    done <= 0;
                    m <= 0;
                    n <= 0;
                end
                S_COUNT: begin
                    busy <= 1;
                    done <= 0;
                    if (idx < 25) begin
                        total_count <= total_count + info_table[idx*2 +: 2];
                        idx <= idx + 1;
                    end
                end
                S_TRAVERSE: begin
                    busy <= 1;
                    done <= 0;
                    if (idx < 25) begin
                        count <= info_table[idx*2 +: 2];
                        m <= idx / 5 + 1;
                        n <= idx % 5 + 1;
                        // 只处理一个维度
                        idx <= idx + 1;
                        // 可在此处根据count做输出或寄存
                    end
                end
                default: ;
            endcase
        end
    end
endmodule