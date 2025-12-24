module matrix_storage #(
    parameter DATAWIDTH =8,        // 数据宽度
    parameter MAXNUM =2,    // 每个维度下最多多少个矩阵
    parameter PICTUREMATRIXSIZE =25 // 矩阵大小
)(
    input wire clk,
    input wire rst_n,
    
    // 写入接口
    input wire write_en,
    input wire [2:0] mat_col,
    input wire [2:0] mat_row,
    input wire [199:0] data_flow,
    
    // 读取接口
    input wire read_en,
    input wire [2:0] rd_col,
    input wire [2:0] rd_row,
    input wire [1:0] rd_mat_index,
    output reg [199:0] rd_data_flow,
    output reg rd_ready,
    output reg err_rd,
    
    output reg [7:0] total_count,
    output wire [49:0] info_table // 00，0个,01，1个，10，2个
);

// 内部存储
reg [199:0] storage [0:49];//可改成多个小存储块
reg [1:0] count [0:24];
wire [49:0] output_50bit;
reg write_en_d1; // 延迟一拍的信号

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        write_en_d1 <= 1'b0;
    end else begin
        write_en_d1 <= write_en; // 暂存当前的 write_en
    end
end
wire write_pulse = write_en & (~write_en_d1);
assign info_table = {
    count[24], count[23], count[22], count[21], count[20],
    count[19], count[18], count[17], count[16], count[15],
    count[14], count[13], count[12], count[11], count[10],
    count[9],  count[8],  count[7],  count[6],  count[5],
    count[4],  count[3],  count[2],  count[1],  count[0]
};
reg next_slot [0:24];

// 地址自动计算流水线
reg [5:0] wt_addr;
reg [5:0] rd_addr;
reg write_en_after_cal;
reg read_en_after_cal;

integer i;

wire [4:0] wt_place = (mat_col - 3'd1) * 3'd5 + (mat_row - 3'd1);
wire [4:0] rd_place = (rd_col - 3'd1) * 3'd5 + (rd_row - 3'd1);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        total_count <= 8'd0;
        rd_ready <= 1'b0;
        err_rd <= 1'b0;
        rd_data_flow <= 200'd0;
        wt_addr <= 6'd0;
        rd_addr <= 6'd0;
        write_en_after_cal <= 1'b0;
        read_en_after_cal <= 1'b0;
        //清空
        for (i = 0; i < 25; i = i + 1) begin
            count[i] <= 2'd0;
            next_slot[i] <= 1'b0;
        end
        
        for (i = 0; i < 50; i = i + 1) begin
            storage[i] <= 200'd0;
        end
        
    end else begin
        rd_ready <= 1'b0;
        err_rd <= 1'b0;
        write_en_after_cal <= 1'b0;
        read_en_after_cal <= 1'b0;
        
        // 第一级：地址计算
        if (write_pulse) begin
            wt_addr <= {wt_place, next_slot[wt_place]};
            write_en_after_cal <= 1'b1;
            
            // 更新计数
            if (count[wt_place] < MAXNUM) begin
                count[wt_place] <= count[wt_place] + 1'b1;
                total_count <= total_count + 1'b1;
            end
            // 切换槽位
            next_slot[wt_place] <= ~next_slot[wt_place];
        end
            // rd地址计算
        
        if (read_en) begin
            if (rd_mat_index < count[rd_place]) begin
                // 仅支持每种尺寸最多2个槽位，地址使用最低位
                rd_addr <= {rd_place, rd_mat_index[0]};
                read_en_after_cal <= 1'b1;
            end else begin
                err_rd <= 1'b1;
            end
        end
        
        // 第二级：数据读写（时序操作）
        if (write_en_after_cal) begin
            storage[wt_addr] <= data_flow;
        end
        
        if (read_en_after_cal) begin
            rd_data_flow <= storage[rd_addr];
            rd_ready <= 1'b1;
        end
    end
end

endmodule