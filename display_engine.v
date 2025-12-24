module operand_selector #(
    parameter MAX_DIM = 5,
    parameter MAX_MATRIX_ID = 2
)(
    input clk,
    input rst_n,
    input selector_en,
    input btn_confirm,
    // 与接收模块通信
    output reg input_read_start,
    input signed [15:0] data_in,
    input input_read_busy,
    input input_read_done,
    // 与信息显示模块通信 (表格)
    input info_table_display_busy,
    output reg info_table_display_start,
    input info_table_display_done,
    // 与信息显示模块通信 (指定维度)
    output reg [2:0] dim_m,
    output reg [2:0] dim_n,
    input info_table_specified_busy,
    output reg info_table_specified_start,
    input info_table_specified_done,
    // 与矩阵内容显示模块通信
    input matrix_display_busy,
    output reg matrix_display_start,
    output reg [199:0] matrix_display,
    input matrix_display_done,
    // 错误信号输出
    output reg error,
    // 输出选中的物理矩阵ID,获取矩阵
    output reg read_en,
    output reg [7:0] rd_col,
    output reg [7:0] rd_row,
    output reg [1:0] rd_mat_index,
    input [199:0] rd_data_flow,
    input rd_ready,
    // 输出选中的矩阵
    output reg [9:0] matrix_phys_id,
    output reg done
);
    // 状态定义
    localparam IDLE                          = 5'd0;
    localparam DISPLAY_INFO_TABLE_ALL        = 5'd1;
    localparam DISPLAY_INFO_TABLE_WAIT       = 5'd2;
    localparam LOAD_DIM_M_REQ                = 5'd3;
    localparam LOAD_DIM_M_WAIT               = 5'd4;
    localparam LOAD_DIM_N_REQ            = 5'd5;
    localparam LOAD_DIM_N_WAIT           = 5'd6; 
    localparam DISPLAY_INFO_TABLE_SPECIFIED  = 5'd7;
    localparam DISPLAY_INFO_TABLE_SPECIFIED_WAIT = 5'd8; 
    localparam LOAD_ID_REQ          = 5'd9; 
    localparam LOAD_ID_WAIT              = 5'd10;
    localparam LOAD_MATRIX_REQ              = 5'd11;
    localparam LOAD_MATRIX_WAIT             = 5'd12;
    localparam DISPLAY_OPERAND               = 5'd13;
    localparam DISPLAY_OPERAND_WAIT          = 5'd14; 
    localparam DONE                          = 5'd15; 
    localparam ERROR                         = 5'd16;
    // 状态寄存器
    reg [4:0] state, next_state;
    // 缓存输入数据
    reg signed [15:0] dim_m_buffer, dim_n_buffer, matrix_id_buffer;
    // 状态转换
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else state <= next_state;
    end
    // 下一状态逻辑
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: 
            if (selector_en) 
                next_state = DISPLAY_INFO_TABLE_ALL;
            DISPLAY_INFO_TABLE_ALL: 
            if(!info_table_display_busy) 
                next_state = DISPLAY_INFO_TABLE_WAIT;
            DISPLAY_INFO_TABLE_WAIT: 
            if (info_table_display_done) 
                next_state = LOAD_DIM_M_REQ;
            LOAD_DIM_M_REQ: 
            if(!input_read_busy) begin
                next_state = LOAD_DIM_M_WAIT;
            end
            LOAD_DIM_M_WAIT: begin
                if (input_read_done) begin
                    // 检查输入
                    if(data_in > {13'b0, MAX_DIM[2:0]} || data_in[15] || data_in == 16'd0) 
                        next_state = ERROR;
                    else 
                        next_state = LOAD_DIM_N_REQ;
                end
            end
            LOAD_DIM_N_REQ: 
            if(!input_read_busy) begin
                next_state = LOAD_DIM_N_WAIT;
            end
            LOAD_DIM_N_WAIT: begin
                if (input_read_done) begin
                    if(data_in > {13'b0, MAX_DIM[2:0]} || data_in[15] || data_in == 16'd0) 
                    //再检查一次
                        next_state = ERROR;
                    else 
                        next_state = DISPLAY_INFO_TABLE_SPECIFIED;
                end
            end
            DISPLAY_INFO_TABLE_SPECIFIED: 
            if(!info_table_specified_busy) 
                next_state = DISPLAY_INFO_TABLE_SPECIFIED_WAIT;
            DISPLAY_INFO_TABLE_SPECIFIED_WAIT: 
            if (info_table_specified_done) 
                next_state = LOAD_ID_REQ;
            LOAD_ID_REQ:
            if(!input_read_busy) begin
                next_state = LOAD_ID_WAIT;
            end 
            LOAD_ID_WAIT: begin
                if (input_read_done) begin
                    if(data_in > {14'b0, MAX_MATRIX_ID[1:0]} || data_in[15] || data_in == 16'd0) 
                        next_state = ERROR;
                    else 
                        next_state = LOAD_MATRIX_REQ;
                end
            end
            DISPLAY_OPERAND: 
            if(!matrix_display_busy) 
                next_state = DISPLAY_OPERAND_WAIT;
            DISPLAY_OPERAND_WAIT: 
            if (!matrix_display_busy && matrix_display_done) 
                next_state = LOAD_MATRIX_REQ;
            LOAD_MATRIX_REQ: 
                if (rd_ready) 
                    next_state = LOAD_MATRIX_WAIT;
            LOAD_MATRIX_WAIT: 
                if (rd_ready) 
                    next_state = DISPLAY_OPERAND;
            DONE:  
                next_state = IDLE;
            ERROR: 
                next_state = IDLE;
            default: 
                next_state = IDLE;
        endcase
    end
    // 输出逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            input_read_start <= 1'b0;
            info_table_display_start <= 1'b0;
            dim_m <= 3'd0; 
            dim_n <= 3'd0; 
            info_table_specified_start <= 1'b0;
            matrix_display_start <= 1'b0;
            error <= 1'b0;
            done <= 1'b0; 
            input_buffer_ready <= 1'b0;
            dim_m_buffer <= 16'd0;
            dim_n_buffer <= 16'd0;
            matrix_id_buffer <= 16'd0;
            read_en <= 1'b0;
            rd_col <= 8'd0;
            rd_row <= 8'd0;
            rd_mat_index <= 2'd0;
            matrix_phys_id <= 10'd0;
        end else begin
            // 默认清除脉冲信号
            info_table_display_start <= 1'b0;
            info_table_specified_start <= 1'b0;
            matrix_display_start <= 1'b0;
            input_read_start <= 1'b0;
            read_en <= 1'b0;
            input_buffer_ready <= 1'b0;
            done <= 1'b0;
            error <= 1'b0;
            
            case (state)
                DISPLAY_INFO_TABLE_ALL: begin
                    info_table_display_start <= 1'b1;
                end
                LOAD_DIM_M_REQ: begin
                    input_read_start <= 1'b1;
                end
                LOAD_DIM_M_WAIT: begin
                    if (input_read_done) begin
                        dim_m_buffer <= data_in;
                    end
                end
                LOAD_DIM_N_REQ: begin
                    input_read_start <= 1'b1;
                end
                LOAD_DIM_N_WAIT: begin
                    if (input_read_done) begin
                        dim_n_buffer <= data_in;
                    end
                end
                DISPLAY_INFO_TABLE_SPECIFIED: begin
                    dim_m <= dim_m_buffer[2:0];
                    dim_n <= dim_n_buffer[2:0];
                    info_table_specified_start <= 1'b1;
                end
                LOAD_ID_REQ: begin
                    input_read_start <= 1'b1;
                end
                LOAD_ID_WAIT: begin
                    if (input_read_done) begin
                        matrix_id_buffer <= data_in;
                    end
                end
                LOAD_MATRIX_REQ: begin
                    read_en <= 1'b1;
                    rd_mat_index <= matrix_id_buffer[1:0];
                    rd_row <= 8'd0;
                    rd_col <= 8'd0;
                end
                LOAD_MATRIX_WAIT: begin
                    // 等待矩阵加载完成
                end
                DISPLAY_OPERAND: begin
                    matrix_display_start <= 1'b1;
                    matrix_display <= rd_data_flow;
                end
                DONE: begin
                    matrix_phys_id <= {dim_m_buffer[2:0], dim_n_buffer[2:0], matrix_id_buffer[1:0]};
                    done <= 1'b1;
                end
                ERROR: begin
                    error <= 1'b1;
                end
            endcase
        end
    end
endmodule