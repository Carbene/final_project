module transposer (
    // 时钟与复位
    input clk,
    input rst_n,
    input transposer_en,
    //待计算数
    input [7:0] matrix_phys_id,
    //读数据接口
    input read_ready,
    output reg read_valid,
    output reg [7:0] matrix_phys_id_read,
    output reg [5:0] addr_read,
    input signed [15:0] data_read,
    //写结果接口
    input write_ready,
    output reg write_valid,
    output reg [6:0] addr_write,
    output reg signed [15:0] data_write,
    //完成信号
    output reg done
);

    localparam IDLE         = 3'd0;
    localparam LOAD_REQ     = 3'd1;
    localparam LOAD_WAIT    = 3'd2;
    localparam WRITE        = 3'd3;
    localparam DONE         = 3'd4;
    //状态寄存器
    reg [2:0] state, next_state;
    // 计数器    
    reg [3:0] cnt_m, cnt_n;
    wire [5:0] total_ops = dim_m * dim_n;
    reg [5:0] ops_cnt;
    wire [3:0] dim_m = matrix_phys_id[7:5];
    wire [3:0] dim_n = matrix_phys_id[4:2];
    // 中间缓存
    reg signed [15:0] data_buffer;
    //状态转移
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else        state <= next_state;
    end
    always @(*) begin
        case (state)
            IDLE:      
                next_state = transposer_en ? LOAD_REQ : IDLE;
            LOAD_REQ: begin 
                if(read_ready && read_valid) begin
                    next_state = LOAD_WAIT;
                end else begin
                    next_state = LOAD_REQ;
                end
            end
            LOAD_WAIT: 
                next_state = WRITE;
            WRITE: begin
                if (ops_cnt == total_ops - 1)
                    next_state = DONE;
                else
                    next_state = LOAD_REQ;
            end
            DONE:begin 
                next_state = IDLE;
            end
            default:begin 
                next_state = IDLE;
            end
        endcase
    end
    //输出逻辑与状态操作
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr_read      <= 6'b0;
            addr_write <= 6'b0;
            data_write  <= 16'b0;
            write_valid    <= 1'b0;
            read_valid     <= 1'b0;
            done        <= 1'b0;
            cnt_m       <= 4'b0;
            cnt_n       <= 4'b0;
            ops_cnt     <= 6'b0;
            data_buffer <= 16'b0;
        end
        else begin
            done  <= 1'b0;
            case (state)
                IDLE: begin
                    cnt_m    <= 4'b0;
                    cnt_n    <= 4'b0;
                    ops_cnt <= 6'b0;
                    addr_read   <= 6'b0; 
                end
                LOAD_REQ: begin
                    read_valid       <= 1'b1;
                    matrix_phys_id_read  <= matrix_phys_id;
                    addr_read       <= ops_cnt;
                end
                LOAD_WAIT: begin
                    read_valid <= 1'b0;
                    data_buffer <= data_read;
                end
                WRITE: begin
                    addr_write <= cnt_n * dim_m + cnt_m;
                    data_write  <= data_buffer;
                    write_valid        <= 1'b1;
                    if(write_ready && write_valid) begin
                        write_valid <= 1'b0;
                        if (ops_cnt < total_ops - 1) begin
                        ops_cnt <= ops_cnt + 1;
                        if (cnt_n == dim_n - 1) begin
                            cnt_n <= 4'b0;
                            cnt_m <= cnt_m + 1;
                        end else begin
                            cnt_n <= cnt_n + 1;
                        end
                    end
                    end
                end
                DONE: begin
                    done <= 1'b1;
                end
            endcase
        end
    end

endmodule