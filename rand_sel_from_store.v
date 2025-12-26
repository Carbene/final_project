// rand_sel_from_store.v
// �? matrix_store �? info_table 中随机�?�择矩阵并�?�过读取接口读取矩阵
// 支持操作�?00 转置（unary）�??01 数乘（unary + 随机 0-9）�??10 加法（需要同�?维度�?2个）�?11 乘法（按列行匹配�?

module rand_sel_from_store(
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [1:0] op_mode, // 00 transpose,01 scalarmul,10 add,11 mul
    input wire [49:0] info_table, // �? matrix_store 直接读取�? 25 �? 2bit 计数（count[24]..count[0])

    // matrix_store 读取接口
    output reg read_en,
    output reg [2:0] rd_col,
    output reg [2:0] rd_row,
    output reg [1:0] rd_mat_index,
    input wire [199:0] rd_data_flow,
    input wire rd_ready,
    input wire err_rd,

    // 输出矩阵与控制信�?
    output reg [199:0] matrix1,
    output reg [199:0] matrix2,
    output reg matrix1_valid,
    output reg matrix2_valid,
    output reg [2:0] dim_m1,
    output reg [2:0] dim_n1,
    output reg [2:0] dim_m2,
    output reg [2:0] dim_n2,
    output reg done,
    output reg fail,
    output reg [3:0] scalar_out // 0..9
);

    // 状�?�机
    localparam S_IDLE   = 4'd0;
    localparam S_SCAN   = 4'd1;
    localparam S_SELECT = 4'd2;
    localparam S_READ1  = 4'd3;
    localparam S_WAIT1  = 4'd4;
    localparam S_READ2  = 4'd5;
    localparam S_WAIT2  = 4'd6;
    localparam S_DONE   = 4'd7;
    localparam S_FAIL   = 4'd8;

    reg [3:0] state, next_state;

    // LFSR 随机�?
    reg [7:0] lfsr;
    wire [7:0] rand8 = lfsr;

    integer i;

    // 候�?�列�?
    reg [4:0] candidates [0:24];
    reg [4:0] cand_cnt;
    reg [4:0] sel_place; // 0..24
    reg [1:0] sel_count; // 存储槽位�?
    reg [1:0] sel_id; // 0 or 1

    // 解码 info_table 中的 count: count(i) 位于 info_table[ (24-i)*2 +:2 ]
    function [1:0] get_count;
        input integer idx;
        integer base;
        begin
            base = (24 - idx) * 2;
            // 使用显式位�?�代�? SystemVerilog 的动态部分切�? (base +: 2)
            get_count = {info_table[base+1], info_table[base]};
        end
    endfunction

    // helper: place -> row(1..5) and col(1..5)
    function [2:0] place_row;
        input [4:0] p;
        begin
            place_row = (p / 5) + 3'd1; // 1..5
        end
    endfunction

    function [2:0] place_col;
        input [4:0] p;
        begin
            place_col = (p % 5) + 3'd1; // 1..5
        end
    endfunction

    // 同步 LFSR
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr <= 8'hA5; // 非零种子
        end else begin
            // �?�? Galois LFSR 8-bit
            lfsr[7:1] <= lfsr[6:0];
            lfsr[0] <= lfsr[7] ^ lfsr[5];
        end
    end

    // 主状态机寄存
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
        end else begin
            state <= next_state;
        end
    end

    // 默认组合逻辑：决定下�?态与读请求信号（短脉冲）
    always @(*) begin
        // 默认�?
        next_state = state;
        rd_col = 3'd0;
        rd_row = 3'd0;
        rd_mat_index = 2'd0;

        case (state)
            S_IDLE: begin
                if (start) begin
                    next_state = S_SCAN;
                end
            end

            S_SCAN: begin
                // build candidate list based on op_mode
                next_state = S_SELECT;
            end

            S_SELECT: begin
                // if no candidate -> fail
                if (cand_cnt == 0) begin
                    next_state = S_FAIL;
                end else begin
                    next_state = S_READ1;
                end
            end

            S_READ1: begin
                // 发出�?�? read_en 脉冲（registered in sequential block�?
                rd_row = place_row(sel_place);
                rd_col = place_col(sel_place);
                rd_mat_index = sel_id;
                next_state = S_WAIT1;
            end

            S_WAIT1: begin
                // 等待 rd_ready 来接收数据（matrix_store 在下�?拍给�? rd_ready�?
                if (rd_ready) begin
                    if (op_mode == 2'b10) begin
                        // 加法：读第一个后�?要再读第二个（同�? place 两个 id�?
                        next_state = S_READ2;
                    end else if (op_mode == 2'b11) begin
                        // 乘法：在读第�?个后，需要根据其 col 去寻找第二个
                        next_state = S_SCAN; // 重用扫描以寻找匹配行
                    end else begin
                        // 单目运算：完�?
                        next_state = S_DONE;
                    end
                end
            end

            S_READ2: begin
                // 第二个矩阵：同一 place，另�? id
                rd_row = place_row(sel_place);
                rd_col = place_col(sel_place);
                rd_mat_index = (sel_id == 2'd0) ? 2'd1 : 2'd0; // 读另�?�?
                next_state = S_WAIT2;
            end

            S_WAIT2: begin
                if (rd_ready) begin
                    next_state = S_DONE;
                end
            end

            S_DONE: begin
                next_state = S_IDLE;
            end

            S_FAIL: begin
                next_state = S_IDLE;
            end
        endcase
    end

    // 顺序逻辑：扫描�?��?��?��?�择并在 rd_ready 时捕获数�?
    reg [4:0] tmp_cand_idx;
    reg [4:0] first_place_for_mul;
    reg first_place_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cand_cnt <= 5'd0;
            tmp_cand_idx <= 5'd0;
            sel_place <= 5'd0;
            sel_count <= 2'd0;
            sel_id <= 2'd0;
            matrix1 <= 200'd0;
            matrix2 <= 200'd0;
            matrix1_valid <= 1'b0;
            matrix2_valid <= 1'b0;
            dim_m1 <= 3'd0;
            dim_n1 <= 3'd0;
            dim_m2 <= 3'd0;
            dim_n2 <= 3'd0;
            done <= 1'b0;
            fail <= 1'b0;
            first_place_for_mul <= 5'd0;
            first_place_valid <= 1'b0;
            scalar_out <= 4'd0;
            read_en <= 1'b0;
        end else begin
            // 默认清理单周期信�?
            matrix1_valid <= 1'b0;
            matrix2_valid <= 1'b0;
            done <= 1'b0;
            fail <= 1'b0;
            read_en <= 1'b0;

            case (state)
                S_IDLE: begin
                    cand_cnt <= 5'd0;
                    tmp_cand_idx <= 5'd0;
                    sel_place <= 5'd0;
                    sel_id <= 2'd0;
                    sel_count <= 2'd0;
                    first_place_valid <= 1'b0;
                    // 在空闲时清零矩阵，避免残留数�?
                    matrix1 <= 200'd0;
                    matrix2 <= 200'd0;
                    read_en <= 1'b0;
                end

                S_SCAN: begin
                    // 重建候�?�列表，针对不同模式
                    cand_cnt <= 5'd0;
                    tmp_cand_idx <= 5'd0;
                    for (i = 0; i < 25; i = i + 1) begin
                        if (op_mode == 2'b10) begin
                            // 加法：需�? count == 2
                            if (get_count(i) == 2'd2) begin
                                candidates[tmp_cand_idx] <= i[4:0];
                                tmp_cand_idx <= tmp_cand_idx + 1'b1;
                            end
                        end else if (op_mode == 2'b11) begin
                            // 乘法：如果还没读到第�?个矩阵，候�?�为 count>0
                            if (!first_place_valid) begin
                                if (get_count(i) != 2'd0) begin
                                    candidates[tmp_cand_idx] <= i[4:0];
                                    tmp_cand_idx <= tmp_cand_idx + 1'b1;
                                end
                            end else begin
                                // 已经读到第一个矩阵，寻找 row == first_col && count>0
                                if (get_count(i) != 2'd0) begin
                                    if (((i / 5) + 1) == place_col(first_place_for_mul)) begin
                                        candidates[tmp_cand_idx] <= i[4:0];
                                        tmp_cand_idx <= tmp_cand_idx + 1'b1;
                                    end
                                end
                            end
                        end else begin
                            // 单目：需�? count>0
                            if (get_count(i) != 2'd0) begin
                                candidates[tmp_cand_idx] <= i[4:0];
                                tmp_cand_idx <= tmp_cand_idx + 1'b1;
                            end
                        end
                    end
                    cand_cnt <= tmp_cand_idx;
                end

                S_SELECT: begin
                    // 选择候�?�中的一个（使用 lfsr % cand_cnt�?
                    if (cand_cnt != 0) begin
                        sel_place <= candidates[ rand8 % cand_cnt ];
                        sel_count <= get_count(candidates[ rand8 % cand_cnt ]);
                        if (get_count(candidates[ rand8 % cand_cnt ]) == 2) begin
                            sel_id <= {1'b0, rand8[0]};
                        end else begin
                            sel_id <= 2'd0;
                        end
                    end
                end

                S_READ1: begin
                    // 发出读请求：在此处产生时序化的单�? read_en 脉冲
                    read_en <= 1'b1;
                end

                S_WAIT1: begin
                    if (rd_ready) begin
                        // 把读到的数据放到 matrix1
                        matrix1 <= rd_data_flow;
                        dim_m1 <= rd_row;
                        dim_n1 <= rd_col;
                        matrix1_valid <= 1'b1;
                        // 特殊处理：如果是乘法，记录第�?�? place 并标�?
                        if (op_mode == 2'b11) begin
                            first_place_for_mul <= sel_place;
                            first_place_valid <= 1'b1;
                        end
                        // 如果是数乘，生成 scalar 0..9
                        if (op_mode == 2'b01) begin
                            scalar_out <= rand8 % 10;
                        end
                    end
                end

                S_READ2: begin
                    // 组合逻辑会发出第二次 read_en（在此处产生时序化脉冲）
                    read_en <= 1'b1;
                end

                S_WAIT2: begin
                    if (rd_ready) begin
                        matrix2 <= rd_data_flow;
                        dim_m2 <= rd_row;
                        dim_n2 <= rd_col;
                        matrix2_valid <= 1'b1;
                    end
                end

                S_DONE: begin
                    done <= 1'b1;
                    read_en <= 1'b0;
                end

                S_FAIL: begin
                    fail <= 1'b1;
                    read_en <= 1'b0;
                    
                end
            endcase
        end
    end

endmodule