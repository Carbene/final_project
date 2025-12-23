module calculation_top#(
        parameter IMAGE_HEIGHT = 10,
        parameter IMAGE_WIDTH  = 12,
        parameter KERNEL_SIZE  = 3,
        parameter CNT_MAX = 21'd1_999_999,
        parameter CNT_WIDTH = 21
    )(
    //时钟与复位
    input clk,
    input rst_n,
    input start,           // 上位机使能
    input btn_confirm,     // 按键确认
    input [2:0]  mode_sw,         // 模式
    input [7:0]  scalar_sw,       // 标量
    // 来自参数设置器的限制
    input [3:0]  dim_m_max,
    input [3:0]  dim_n_max,
    //报错计数器相关端口
    output error,
    input timer_done,
    //矩阵内容显示模块相关端口
    output matrix_result_display_start,
    input  matrix_result_display_done,
    input  matrix_result_display_busy,
    output [2:0]   calculation_display,
    //内存读相关端口
    input  read_ready,
    output read_valid,
    output [7:0] matrix_phys_id_read,
    output [5:0] addr_read,
    input  signed [15:0] data_read,
    //内存读图像相关端口
    input  read_image_ready,
    output read_image_valid,
    output [5:0] addr_image_read,
    input  signed [15:0] data_image_read,
    //内存写相关端口
    input  write_ready,
    output write_valid,
    output [6:0] addr_write,
    output signed [15:0] data_write,
    // IO接口相关端口
    output input_buffer_ready,
    input input_buffer_valid,
    input [15:0] data_in,
    // 与信息显示模块通信 (表格)
    output reg info_table_display_start,
    input info_table_display_busy,
    input info_table_display_done,
    // 与信息显示模块通信 (指定维度)
    output reg [3:0] dim_m,
    output reg [3:0] dim_n,
    output reg info_table_specified_start,
    input info_table_specified_busy,
    input info_table_specified_done,
    //与矩阵内容显示模块通信
    output reg matrix_display_start,
    output reg [7:0] matrix_id_display,
    input matrix_display_done,
    input matrix_display_busy,
    //与时钟周期统计器显示模块通信
    input clk_cycle_display_busy,
    output clk_cycle_display_start,
    output [15:0] clk_cycle_display_data,
    input clk_cycle_display_done,
    //能否离开当前模式
    output exitable
);
    wire selector_en, selector_done, selector_error;
    wire [7:0] matrix_phys_id;
    wire adder_en, multiplier_en, scalar_multiplier_en, transposer_en, convoluter_en;
    wire adder_done, multiplier_done, scalar_multiplier_done, transposer_done, convoluter_done;
    wire [7:0] matrix_a_phys_id, matrix_b_phys_id;
    wire signed [15:0] scalar_out;
    wire [15:0] clock_cycles;
    wire btn_confirm_debounced;
    wire adder_rv, mult_rv, scal_rv, trans_rv, conv_rv;
    wire [7:0] adder_rid, mult_rid, scal_rid, trans_rid, conv_rid;
    wire [5:0] adder_ra, mult_ra, scal_ra, trans_ra, conv_ra;
    
    wire adder_wv, mult_wv, scal_wv, trans_wv, conv_wv;
    wire [6:0] adder_wa, mult_wa, scal_wa, trans_wa, conv_wa;
    wire [15:0] adder_wd, mult_wd, scal_wd, trans_wd, conv_wd;
    // 读总线切换
    assign read_valid = adder_en ? adder_rv : (multiplier_en ? mult_rv : (scalar_multiplier_en ? scal_rv : (transposer_en ? trans_rv : (convoluter_en ? conv_rv : 1'b0))));
    assign matrix_phys_id_read = adder_en ? adder_rid : (multiplier_en ? mult_rid : (scalar_multiplier_en ? scal_rid : (transposer_en ? trans_rid : (convoluter_en ? conv_rid : 8'd0))));
    assign addr_read  = adder_en ? adder_ra  : (multiplier_en ? mult_ra  : (scalar_multiplier_en ? scal_ra  : (transposer_en ? trans_ra  : (convoluter_en ? conv_ra  : 6'd0))));
    // 写总线切换
    assign write_valid = adder_en ? adder_wv : (multiplier_en ? mult_wv : (scalar_multiplier_en ? scal_wv : (transposer_en ? trans_wv : (convoluter_en ? conv_wv : 1'b0))));
    assign addr_write  = adder_en ? adder_wa  : (multiplier_en ? mult_wa  : (scalar_multiplier_en ? scal_wa  : (transposer_en ? trans_wa  : (convoluter_en ? conv_wa  : 7'd0))));
    assign data_write  = adder_en ? adder_wd  : (multiplier_en ? mult_wd  : (scalar_multiplier_en ? scal_wd  : (transposer_en ? trans_wd  : (convoluter_en ? conv_wd  : 16'd0))));
    // done 信号总线
    assign done = adder_done | multiplier_done | scalar_multiplier_done | transposer_done | convoluter_done;
    calculator_subsystem u_calculator_subsystem (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .btn_confirm(btn_confirm_debounced),
        .mode_sw(mode_sw),
        .scalar_sw(scalar_sw),
        .dim_m_max(dim_m_max),
        .dim_n_max(dim_n_max), 
        .selector_en(selector_en),
        .selector_done(selector_done),
        .selector_error(selector_error),
        .matrix_phys_id(matrix_phys_id),
        .error(error),
        .timer_done(timer_done), 
        .adder_en(adder_en),
        .multiplier_en(multiplier_en), 
        .scalar_multiplier_en(scalar_multiplier_en),
        .transposer_en(transposer_en), 
        .convoluter_en(convoluter_en),
        .adder_done(adder_done), 
        .multiplier_done(multiplier_done), 
        .scalar_multiplier_done(scalar_multiplier_done), 
        .transposer_done(transposer_done), 
        .convoluter_done(convoluter_done),
        .matrix_result_display_start(matrix_result_display_start),
        .matrix_result_display_done(matrix_result_display_done),
        .matrix_result_display_busy(matrix_result_display_busy),
        .matrix_a_phys_id(matrix_a_phys_id),
        .matrix_b_phys_id(matrix_b_phys_id),
        .scalar_out(scalar_out),
        .calculation_display(calculation_display), 
        .exitable(exitable)
    );
    adder u_adder(
        .matrix_a_id(matrix_a_phys_id),
        .matrix_b_id(matrix_b_phys_id),
        .adder_en(adder_en),
        .read_ready(read_ready),
        .read_valid(adder_rv),
        .matrix_phys_id_read(adder_rid),
        .addr_read(adder_ra),
        .data_read(data_read),
        .write_ready(write_ready),
        .write_valid(adder_wv),
        .addr_write(adder_wa),
        .data_write(adder_wd),
        .done(adder_done)
    );
    convoluter #(
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .KERNEL_SIZE(KERNEL_SIZE)
    )u_convoluter(
        .clk(clk),
        .rst_n(rst_n),
        .convoluter_en(convoluter_en),
        .matrix_phys_id(matrix_a_phys_id),
        .read_ready(read_ready),
        .read_valid(conv_rv),
        .matrix_phys_id_read(conv_rid),
        .addr_read(addr_read),
        .data_read(data_read),
        .read_image_ready(read_image_ready),
        .read_image_valid(read_image_valid),
        .addr_image_read(addr_image_read),
        .data_image_read(data_image_read),
        .write_conv_result_ready(write_ready),
        .write_conv_result_valid(conv_wv),
        .addr_conv_result_write(conv_wa),
        .data_conv_result_write(conv_wd),
        .clk_cycle_display_busy(clk_cycle_display_busy),
        .clk_cycle_display_start(clk_cycle_display_start),
        .clk_cycle_display_data(clk_cycle_display_data),
        .clk_cycle_display_done(clk_cycle_display_done),
        .done(convoluter_done)
    );
    multiplier u_multiplier(
        .clk(clk),
        .rst_n(rst_n),
        .multiplier_en(multiplier_en),
        .matrix_a_id(matrix_a_phys_id),
        .matrix_b_id(matrix_b_phys_id),
        .matrix_result_id(matrix_result_phys_id),
        .read_ready(read_ready),
        .read_valid(mult_rv),
        .matrix_id_read(mult_rid),
        .addr_read(mult_ra),
        .data_read(data_read),
        .write_ready(write_ready),
        .write_valid(mult_wv),
        .addr_write(mult_wa),
        .data_write(mult_wd),
        .done(multiplier_done)
    );
    operand_selector u_operand_selector(
        .clk(clk),
        .rst_n(rst_n),
        .selector_en(selector_en),
        .btn_confirm(btn_confirm_debounced),
        .dim_m_max(dim_m_max),
        .dim_n_max(dim_n_max),
        .matrix_id_max(matrix_id_max),
        .input_buffer_ready(input_buffer_ready),
        .data_in(data_in),
        .input_buffer_valid(input_buffer_valid),
        .info_table_display_busy(info_table_display_busy),
        .info_table_display_start(info_table_display_start),
        .info_table_display_done(info_table_display_done),
        .dim_m(dim_m),
        .dim_n(dim_n),
        .info_table_specified_busy(info_table_specified_busy),
        .info_table_specified_start(info_table_specified_start),
        .info_table_specified_done(info_table_specified_done),
        .matrix_display_busy(matrix_display_busy),
        .matrix_display_start(matrix_display_start),
        .matrix_id_display(matrix_id_display),
        .matrix_display_done(matrix_display_done),
        .error(selector_error),
        .matrix_phys_id(matrix_phys_id),
        .done(selector_done)
    );

    scalar_multiplier u_scalar_multiplier(
        .clk(clk),
        .rst_n(rst_n),
        .scalar_multiplier_en(scalar_multiplier_en),
        .matrix_phys_id(matrix_phys_id),
        .matrix_phys_id_result(matrix_result_phys_id),
        .scalar(scalar_out),
        .read_ready(read_ready),
        .read_valid(scal_rv),
        .matrix_phys_id_read(scal_rid),
        .addr_read(scal_ra),
        .data_read(data_read),
        .write_ready(write_ready),
        .write_valid(scal_wv),
        .addr_write(scal_wa),
        .data_write(scal_wd),
        .done(scalar_multiplier_done)
);
    transposer u_transposer(
        .clk(clk),
        .rst_n(rst_n),
        .transposer_en(transposer_en),
        .matrix_phys_id(matrix_phys_id),
        .read_ready(read_ready),
        .read_valid(transposer_rv),
        .matrix_phys_id_read(transposer_rid),
        .addr_read(transposer_ra),
        .data_read(data_read),
        .write_ready(write_ready),
        .write_valid(transposer_wv),
        .addr_write(transposer_wa),
        .data_write(transposer_wd),
        .done(transposer_done)
);
    btn_debouncer #(
    .CNT_MAX(CNT_MAX),
    .CNT_WIDTH(CNT_WIDTH)
    )u_debouncer_confirm(
    .clk(clk),
    .rst_n(rst_n),
    .btn_in(btn_confirm),
    .btn_flag(btn_confirm_debounced)
    );
endmodule
    