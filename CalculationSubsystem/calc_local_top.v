//==============================================================================
// 计算子系统局部顶层模块
// 连接: calculator_subsystem + operand_selector + matrix_alu
//==============================================================================
module calc_local_top (
    // 时钟与复位
    input wire clk,
    input wire rst_n,
    
    // 外部控制信号
    input wire enable,
    input wire btn_confirm,
    input wire btn_restart,
    input wire [4:0] sw,
    
    // 外部计时器接口
    input wire timer_done,
    
    // 与input_buffer通信 (外部接口)
    input wire signed [15:0] data_in,
    input wire input_read_busy,
    input wire input_read_done,
    output wire input_read_start,
    
    // 与信息显示模块通信 - 表格 (外部接口)
    input wire info_table_display_busy,
    input wire info_table_display_done,
    output wire info_table_display_start,
    
    // 与信息显示模块通信 - 指定维度 (外部接口)
    input wire info_table_specified_busy,
    input wire info_table_specified_done,
    output wire info_table_specified_start,
    output wire [2:0] info_dim_m,
    output wire [2:0] info_dim_n,
    
    // 与矩阵内容显示模块通信 (外部接口)
    input wire matrix_display_busy,
    input wire matrix_display_done,
    output wire matrix_display_start,
    output wire [199:0] matrix_display,
    
    // 与矩阵存储模块通信 (外部接口)
    input wire [199:0] rd_data_flow,
    input wire rd_ready,
    output wire read_en,
    output wire [7:0] rd_col,
    output wire [7:0] rd_row,
    output wire [1:0] rd_mat_index,
    
    // 与结果显示模块通信 (外部接口)
    input wire matrix_result_display_busy,
    input wire matrix_result_display_done,
    output wire matrix_result_display_start,
    output wire [2:0] result_m_display,
    output wire [2:0] result_n_display,
    output wire [399:0] result_display,
    
    // 状态输出
    output wire error_calculator,
    output wire exitable
);

    //==========================================================================
    // 内部互联信号
    //==========================================================================
    
    // calculator_subsystem <-> operand_selector
    wire selector_en;
    wire selector_done;
    wire selector_error;
    wire [199:0] selected_matrix;
    wire [2:0] selected_dim_m;
    wire [2:0] selected_dim_n;
    
    // calculator_subsystem <-> matrix_alu
    wire [2:0] op_code;
    wire start_calculation;
    wire [2:0] m_a, n_a;
    wire [199:0] matrix_a_flat;
    wire [2:0] m_b, n_b;
    wire [199:0] matrix_b_flat;
    wire [7:0] scalar;
    wire [399:0] result_flat;
    wire [2:0] result_m, result_n;
    wire alu_done;
    wire alu_busy;

    //==========================================================================
    // 模块实例化
    //==========================================================================
    
    // 计算子系统控制器
    calculator_subsystem u_calculator_subsystem (
        // 时钟与复位
        .clk                        (clk),
        .rst_n                      (rst_n),
        
        // 控制信号
        .enable                     (enable),
        .btn_confirm                (btn_confirm),
        .btn_restart                (btn_restart),
        .sw                         (sw),
        
        // 与operand_selector互联
        .selector_en                (selector_en),
        .selector_done              (selector_done),
        .selector_error             (selector_error),
        .matrix                     (selected_matrix),
        .dim_m                      (selected_dim_m),
        .dim_n                      (selected_dim_n),
        
        // 外部计时器
        .error_calculator           (error_calculator),
        .timer_done                 (timer_done),
        
        // 与matrix_alu互联
        .op_code                    (op_code),
        .start_calculation          (start_calculation),
        .m_a                        (m_a),
        .n_a                        (n_a),
        .matrix_a_flat              (matrix_a_flat),
        .m_b                        (m_b),
        .n_b                        (n_b),
        .matrix_b_flat              (matrix_b_flat),
        .scalar                     (scalar),
        .result_flat                (result_flat),
        .result_m                   (result_m),
        .result_n                   (result_n),
        .done_calculation           (alu_done),
        .busy                       (alu_busy),
        
        // 与结果显示模块通信 (外部接口)
        .matrix_result_display_start(matrix_result_display_start),
        .result_m_display           (result_m_display),
        .result_n_display           (result_n_display),
        .result_display             (result_display),
        .matrix_result_display_done (matrix_result_display_done),
        .matrix_result_display_busy (matrix_result_display_busy),
        
        // 状态输出
        .exitable                   (exitable)
    );
    
    // 操作数选择器
    operand_selector #(
        .MAX_DIM        (5),
        .MAX_MATRIX_ID  (2)
    ) u_operand_selector (
        .clk                        (clk),
        .rst_n                      (rst_n),
        
        // 与calculator_subsystem互联
        .selector_en                (selector_en),
        .btn_confirm                (btn_confirm),
        
        // 与input_buffer通信 (外部接口)
        .input_read_start           (input_read_start),
        .data_in                    (data_in),
        .input_read_busy            (input_read_busy),
        .input_read_done            (input_read_done),
        
        // 与信息显示模块通信 - 表格 (外部接口)
        .info_table_display_busy    (info_table_display_busy),
        .info_table_display_start   (info_table_display_start),
        .info_table_display_done    (info_table_display_done),
        
        // 与信息显示模块通信 - 指定维度 (外部接口)
        .dim_m                      (info_dim_m),
        .dim_n                      (info_dim_n),
        .info_table_specified_busy  (info_table_specified_busy),
        .info_table_specified_start (info_table_specified_start),
        .info_table_specified_done  (info_table_specified_done),
        
        // 与矩阵内容显示模块通信 (外部接口)
        .matrix_display_busy        (matrix_display_busy),
        .matrix_display_start       (matrix_display_start),
        .matrix_display             (matrix_display),
        .matrix_display_done        (matrix_display_done),
        
        // 错误信号输出 -> calculator_subsystem
        .error                      (selector_error),
        
        // 与矩阵存储模块通信 (外部接口)
        .read_en                    (read_en),
        .rd_col                     (rd_col),
        .rd_row                     (rd_row),
        .rd_mat_index               (rd_mat_index),
        .rd_data_flow               (rd_data_flow),
        .rd_ready                   (rd_ready),
        
        // 输出选中的矩阵 -> calculator_subsystem
        .matrix_phys_id             (),  // 未使用
        .done                       (selector_done)
    );
    
    // 将operand_selector的rd_data_flow作为选中的矩阵输出
    assign selected_matrix = rd_data_flow;
    assign selected_dim_m = info_dim_m;
    assign selected_dim_n = info_dim_n;
    
    // 矩阵ALU
    matrix_alu u_matrix_alu (
        .clk                        (clk),
        .rst_n                      (rst_n),
        
        // 与calculator_subsystem互联
        .op_code                    (op_code),
        .start                      (start_calculation),
        
        // 矩阵A输入
        .matrix_a_flat              (matrix_a_flat),
        .m_a                        (m_a),
        .n_a                        (n_a),
        
        // 矩阵B输入
        .matrix_b_flat              (matrix_b_flat),
        .m_b                        (m_b),
        .n_b                        (n_b),
        
        // 标量输入
        .scalar                     (scalar),
        
        // 结果输出 -> calculator_subsystem
        .result_flat                (result_flat),
        .result_m                   (result_m),
        .result_n                   (result_n),
        .done                       (alu_done),
        .busy                       (alu_busy)
    );

endmodule
