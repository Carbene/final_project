// ========================================
// 系统顶层模块 sys_top
// ========================================
// 功能: 矩阵运算系统顶层集成
// 
// 主要功能模块:
// 1. 数据输入模式: UART接收 -> 解析 -> 存储 -> 打印回显
// 2. 生成模式: 随机生成矩阵 -> 存储 -> 打印
// 3. 显示模式: 查询并显示已存储的矩阵
// 4. 计算模式: 矩阵运算 (待实现)
//
// 数据流:
//   UART RX -> Parser/Generator -> Matrix Storage -> Display/Calculate
//                                                  -> UART TX
// ========================================

module sys_top(
	input wire clk,
	input wire rst_n,
	input wire [7:0] command,
	input wire btn_confirm,
	input wire btn_exit,
	input wire uart_rxd,
	output wire uart_txd,
	output reg [7:0] ld2,
	output reg [7:0] led,
	output reg [7:0] dk1_segments,
	output reg [7:0] dk2_segments,
	output reg [7:0] dk_digit_select
);


	// --- 按键防抖 Button Debouncer ---
	wire btn_confirm_db;
	btn_debouncer u_btn_debouncer(
		.clk(clk),
		.rst_n(rst_n),
		.btn_in(btn_confirm),
		.btn_out(),
        .pulse(btn_confirm_db)
	);
    // --- UART RX 串口接收 ---
	wire uart_rx_done;
	wire [7:0] uart_rx_data;
	uart_rx u_uart_rx(
		.clk(clk),
		.rst_n(rst_n),
		.uart_rxd(uart_rxd),
		.uart_rx_done(uart_rx_done),
		.uart_rx_data(uart_rx_data)
	);
    // --- UART TX ---
	reg uart_tx_en;
	reg [7:0] uart_tx_data;
	reg print_sent;
	wire uart_tx_busy;
	// --- print??????? ---
	wire print_busy, print_done, print_dout_valid;
	wire [7:0] print_dout;

	uart_tx u_tx(
		.clk(clk),
		.rst_n(rst_n),
		.uart_tx_en(uart_tx_en),
		.uart_tx_data(uart_tx_data),
		.uart_txd(uart_txd),
		.uart_tx_busy(uart_tx_busy)
	);

	// --- Central Controller ---
	wire data_input_mode_en;
	wire generate_mode_en;
	wire display_mode_en;
	wire calculation_mode_en;
	

    // modeָʾ??
    wire [7:0] led_wire;
    assign led_wire={4'b0,data_input_mode_en,generate_mode_en,display_mode_en,calculation_mode_en};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            led <= 8'd0;
        end
        else begin
            led <= led_wire;
        end
    end

	Central_Controller u_ctrl(
		.clk(clk),
		.rst_n(rst_n),
		.command(command[2:0]),
		.btn_confirm(btn_confirm_db),
		
		.data_input_mode_en(data_input_mode_en),
		
		.generate_mode_en(generate_mode_en),
		
		.display_mode_en(display_mode_en),
		
		.calculation_mode_en(calculation_mode_en)
	);

	// --- LED状态指示灯控制 ---
	reg led0_on;
	reg [24:0] led0_cnt; // 0.5秒闪烁计数器，50MHz时钟下0.5s=25_000_000
	reg led1_on; // gen_done状态指示
	reg [24:0] led1_cnt;
	reg led2_on; // gen_error状态指示
	reg [24:0] led2_cnt;
	reg led3_on; // gen_valid状态指示
	reg [24:0] led3_cnt;
	wire [7:0] ld2_wire;
	assign ld2_wire = {7'd0, led0_on};

	// 数码管输出 (当前未使用，预留)
	// assign seg_data0 = 8'd0;
	// assign seg_data1 = 8'd0;
	// assign seg_sel0 = 8'd0;
	// assign seg_sel1 = 8'd0;

	// --- LED0闪烁控制 (存储指示) ---
	always @(posedge clk or negedge rst_n) begin
	    if (!rst_n) begin
	        led0_on <= 1'b0;
	        led0_cnt <= 23'd0;
	    end else if (store_write_en) begin
	        led0_on <= 1'b1;
	        led0_cnt <= 23'd0;
	    end else if (led0_on) begin
	        if (led0_cnt < 25'd24_999_999) begin
	            led0_cnt <= led0_cnt + 1'b1;
	        end else begin
	            led0_on <= 1'b0;
	        end
	    end
	end

	// --- LED1闪烁控制 (生成完成指示) ---
	always @(posedge clk or negedge rst_n) begin
	    if (!rst_n) begin
	        led1_on <= 1'b0;
	        led1_cnt <= 25'd0;
	    end else if (gen_done) begin
	        led1_on <= 1'b1;
	        led1_cnt <= 25'd0;
	    end else if (led1_on) begin
	        if (led1_cnt < 25'd24_999_999) begin
	            led1_cnt <= led1_cnt + 1'b1;
	        end else begin
	            led1_on <= 1'b0;
	        end
	    end
	end

	// --- LED2闪烁控制 (生成错误指示) ---
	always @(posedge clk or negedge rst_n) begin
	    if (!rst_n) begin
	        led2_on <= 1'b0;
	        led2_cnt <= 25'd0;
	    end else if (gen_error) begin
	        led2_on <= 1'b1;
	        led2_cnt <= 25'd0;
	    end else if (led2_on) begin
	        if (led2_cnt < 25'd24_999_999) begin
	            led2_cnt <= led2_cnt + 1'b1;
	        end else begin
	            led2_on <= 1'b0;
	        end
	    end
	end

	// --- LED3闪烁控制 (生成有效指示) ---
	always @(posedge clk or negedge rst_n) begin
	    if (!rst_n) begin
	        led3_on <= 1'b0;
	        led3_cnt <= 25'd0;
	    end else if (gen_valid) begin
	        led3_on <= 1'b1;
	        led3_cnt <= 25'd0;
	    end else if (led3_on) begin
	        if (led3_cnt < 25'd24_999_999) begin
	            led3_cnt <= led3_cnt + 1'b1;
	        end else begin
	            led3_on <= 1'b0;
	        end
	    end
	end

    // LD2灯组赋值 (综合状态显示)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ld2 <= 8'd0;
        end else begin
            ld2[0] <= ld2_wire[0];  // 矩阵存储指示
            ld2[1] <= led1_on;      // gen_done生成完成
            ld2[2] <= led2_on;      // gen_error生成错误
            ld2[3] <= led3_on;      // gen_valid生成有效
            ld2[4] <= ~debug_state[0]; // print_table状态机调试
            ld2[5] <= ~debug_state[1];
            ld2[6] <= ~debug_state[2];
            ld2[7] <= ~debug_state[3];
        end
    end

	// --- UART Parser 串口解析器 ---
	// 功能: 解析UART接收的矩阵数据格式
	// 输入: uart_rx_data, uart_rx_done, data_input_mode_en
	// 输出: parsed_m, parsed_n, parsed_matrix_flat, parse_done, parse_error
	wire [2:0] parsed_m, parsed_n;
	wire [199:0] parsed_matrix_flat;
	wire parse_done, parse_error;
	uart_parser u_parser(
		.clk(clk),
		.rst_n(rst_n),
		.rx_data(uart_rx_data),
		.rx_done(uart_rx_done),
		.parse_enable(data_input_mode_en),
		.elem_min(8'd0),
		.elem_max(8'd9),
		.parsed_m(parsed_m),
		.parsed_n(parsed_n),
		.parsed_matrix_flat(parsed_matrix_flat),
		.parse_done(parse_done),
		.parse_error(parse_error)
	);
	// --- Matrix Store 矩阵存储控制逻辑 ---
	// 功能: 将解析或生成的矩阵写入存储模块
	// 触发条件: parse_done (解析完成) 或 gen_valid (生成有效)
	reg store_write_en;
	reg [2:0] store_mat_col;
	reg [2:0] store_mat_row;
	reg [199:0] store_data_flow;
	always @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			store_write_en <= 1'b0;
			store_mat_col <= 3'd0;
			store_mat_row <= 3'd0;
			store_data_flow <= 200'd0;
		end else if (parse_done) begin
			// 数据输入模式: 存储解析后的矩阵
			store_write_en <= 1'b1;
			store_mat_col <= parsed_m;
			store_mat_row <= parsed_n;
			store_data_flow <= parsed_matrix_flat;
		end else if (gen_valid) begin
			// 生成模式: 存储生成的矩阵
			store_write_en <= 1'b1;
			store_mat_col <= gen_m;
			store_mat_row <= gen_n;
			store_data_flow <= gen_flow;
		end else begin
			store_write_en <= 1'b0;
		end
	end

	// --- Matrix Storage 矩阵存储模块 ---
	// 用于存储解析和生成的矩阵数据
	wire [49:0] info_table;        // 矩阵信息表 (每个矩阵5字节:行、列、ID等)
	wire [7:0] total_count;        // 已存储矩阵总数
	wire store_read_en;            // 读使能 (连接到display模块)
	wire [2:0] store_rd_col;       // 读取的矩阵列数
	wire [2:0] store_rd_row;       // 读取的矩阵行数
	wire [1:0] store_rd_mat_index; // 读取的矩阵索引
	wire [199:0] store_rd_data_flow; // 读取的矩阵数据流
	wire store_rd_ready;           // 读取准备信号
	wire store_err_rd;             // 读取错误信号
	
	matrix_storage #(
		.DATAWIDTH(8),
		.MAXNUM(2),
		.PICTUREMATRIXSIZE(25)
	) u_store (
		.clk(clk),
		.rst_n(rst_n),
		// 写接口 - 连接到parse和generate模块
		.write_en(store_write_en),
		.mat_col(store_mat_col),
		.mat_row(store_mat_row),
		.data_flow(store_data_flow),
		// 读接口 - 连接到display模块
		.read_en(store_read_en),
		.rd_col(store_rd_col),
		.rd_row(store_rd_row),
		.rd_mat_index(store_rd_mat_index),
		.rd_data_flow(store_rd_data_flow),
		.rd_ready(store_rd_ready),
		.err_rd(store_err_rd),
		// 状态输出
		.total_count(total_count),
		.info_table(info_table)
	);
	
	// --- Generate Mode 矩阵生成模式 ---
	// 功能: 根据UART输入的参数随机生成矩阵
	// 复用UART RX的数据流
	wire [7:0] uart_data_gen;
	assign uart_data_gen = uart_rx_data;
	wire [199:0] gen_flow;
	wire gen_done;
	wire gen_error;
	wire gen_valid;
	wire [2:0] gen_m, gen_n;
	generate_mode u_generate_operate(
		.clk(clk),
		.rst_n(rst_n),
		.start(generate_mode_en),
		.uart_data(uart_data_gen),
		.uart_data_valid(uart_rx_done),
		.gen_matrix_flat(gen_flow),
		.gen_m(gen_m),
		.gen_n(gen_n),
		.gen_done(gen_done),
		.gen_valid(gen_valid),
		.error(gen_error)
	);

	// --- Print打印控制 UART TX多路复用 ---
	// Parse模式的UART输出信号
	wire uart_tx_en_parse;
	wire [7:0] uart_tx_data_parse;
	wire print_done_parse;

	// Generate模式的UART输出信号
	wire uart_tx_en_gen;
	wire [7:0] uart_tx_data_gen;
	wire print_done_gen;

	// Display模式的UART输出信号
	wire uart_tx_en_display;
	wire [7:0] uart_tx_data_display;

	// UART TX多路复用器 - 根据当前模式选择输出源
	always @(*) begin
		if (data_input_mode_en) begin
			// 数据输入模式 - 输出解析后的矩阵
			uart_tx_en = uart_tx_en_parse;
			uart_tx_data = uart_tx_data_parse;
		end else if (generate_mode_en) begin
			// 生成模式 - 输出生成的矩阵
			uart_tx_en = uart_tx_en_gen;
			uart_tx_data = uart_tx_data_gen;
		end else if (display_mode_en) begin
			// 显示模式 - 输出表格或指定矩阵
			if(print_busy_table) begin
				uart_tx_en = uart_tx_en_table;
				uart_tx_data = uart_tx_data_table;
			end else begin
				uart_tx_en = uart_tx_en_spec;
				uart_tx_data = uart_tx_data_spec;
			end
		end else begin
			uart_tx_en = 1'b0;
			uart_tx_data = 8'd0;
		end
	end

	// --- Matrix Printer for Parse 解析模式矩阵打印 ---
	// 数据流: uart_parser -> parsed_matrix_flat -> matrix_printer -> UART TX
	matrix_printer u_print_for_parse (
		.clk(clk),
		.rst_n(rst_n),
		.start(parse_done),              // 解析完成时启动打印
		.matrix_flat(parsed_matrix_flat), // 输入: 解析后的矩阵数据
		.dimM(parsed_m),                 // 输入: 矩阵行数
		.dimN(parsed_n),                 // 输入: 矩阵列数
		.use_crlf(1'b1),                 // 使用回车换行
		.tx_start(uart_tx_en_parse),     // 输出: UART发送使能
		.tx_data(uart_tx_data_parse),    // 输出: UART发送数据
		.tx_busy(uart_tx_busy),          // 输入: UART忙状态
		.done(print_done_parse)          // 输出: 打印完成
	);
	
    // --- Matrix Printer for Generate 生成模式矩阵打印 ---
    // 数据流: generate_mode -> gen_flow -> matrix_printer -> UART TX
	matrix_printer u_print_for_generate (
		.clk(clk),
		.rst_n(rst_n),
		.start(gen_valid),            // 生成有效时启动打印
		.matrix_flat(gen_flow),       // 输入: 生成的矩阵数据
		.dimM(gen_m),                 // 输入: 生成的矩阵行数
		.dimN(gen_n),                 // 输入: 生成的矩阵列数
		.use_crlf(1'b1),              // 使用回车换行
		.tx_start(uart_tx_en_gen),    // 输出: UART发送使能
		.tx_data(uart_tx_data_gen),   // 输出: UART发送数据
		.tx_busy(uart_tx_busy),       // 输入: UART忙状态
		.done(print_done_gen)         // 输出: 打印完成
	);
	
	// ========== Display Mode 显示模式 ==========
	// 数据流: display_mode_en -> matrix_selector_display -> print_table 或 print_specified_dim_matrix
	//        -> matrix_storage (读取) -> matrix_printer -> UART TX
	
	// --- Print Table 打印表格信号 ---
	wire uart_tx_en_table;           // 表格打印UART使能
	wire [7:0] uart_tx_data_table;   // 表格打印UART数据
	wire print_busy_table;           // 表格打印忙状态
	wire print_done_table;           // 表格打印完成
	wire print_table_start;          // 表格打印启动信号
	wire [3:0] debug_state;          // 调试状态 (用于LED显示)
	
	// Print Table 模块 - 打印矩阵信息表
	// 数据流: info_table -> print_table -> UART TX
	print_table u_print_table (
		.clk(clk),
		.rst_n(rst_n),
		.start(print_table_start),         // 输入: 启动打印表格
		.uart_tx_busy(uart_tx_busy),       // 输入: UART忙状态
		.uart_tx_en(uart_tx_en_table),     // 输出: UART发送使能
		.uart_tx_data(uart_tx_data_table), // 输出: UART发送数据
		.info_table(info_table),           // 输入: 矩阵信息表
		.cnt(total_count),                 // 输入: 矩阵总数
		.busy(print_busy_table),           // 输出: 模块忙状态
		.done(print_done_table),           // 输出: 打印完成
		.current_state(debug_state)        // 输出: 当前状态
	);

	// --- Print Specified Matrix 打印指定矩阵信号 ---
	wire print_spec_start;               // 启动打印指定矩阵
	wire [2:0] spec_dim_m, spec_dim_n;   // 用户输入的目标矩阵维度
	wire print_spec_busy;                // 打印指定矩阵忙状态
	wire print_spec_done;                // 打印指定矩阵完成
	wire print_spec_error;               // 打印指定矩阵错误
	
	// Matrix Printer for Display 显示模式矩阵打印信号
	wire matrix_print_start;             // 启动矩阵打印
	wire [199:0] matrix_flat;            // 要打印的矩阵数据
	wire [2:0] matrix_dim_m, matrix_dim_n; // 矩阵维度
	wire matrix_print_busy;              // 矩阵打印忙状态
	wire matrix_print_done;              // 矩阵打印完成
	wire uart_tx_en_spec;                // 指定矩阵打印UART使能
	wire [7:0] uart_tx_data_spec;        // 指定矩阵打印UART数据
	
	// Display模式状态信号
	wire display_error;                  // 显示模式错误
	wire display_done;                   // 显示模式完成
	wire [1:0] selected_matrix_id;       // 选中的矩阵ID

	// Matrix Selector Display 矩阵选择显示控制器
	// 数据流: uart_rx -> matrix_selector_display -> (print_table 或 print_specified_dim_matrix)
	matrix_selector_display u_matrix_selector_display (
		.clk(clk),
		.rst_n(rst_n),
		.start(display_mode_en),              // 输入: 显示模式使能
		
		// 与print_table模块的连接
		.print_table_start(print_table_start), // 输出: 启动打印表格
		.print_table_busy(print_busy_table),   // 输入: 表格打印忙
		.print_table_done(print_done_table),   // 输入: 表格打印完成
		
		// UART输入 - 接收用户输入的维度
		.uart_input_data(uart_rx_data),        // 输入: UART接收数据
		.uart_input_valid(uart_rx_done),       // 输入: UART接收有效
		
		// 与print_specified_dim_matrix模块的连接
		.print_spec_start(print_spec_start),   // 输出: 启动打印指定矩阵
		.spec_dim_m(spec_dim_m),               // 输出: 目标矩阵行数
		.spec_dim_n(spec_dim_n),               // 输出: 目标矩阵列数
		.print_spec_busy(print_spec_busy),     // 输入: 指定打印忙
		.print_spec_done(print_spec_done),     // 输入: 指定打印完成
		.print_spec_error(print_spec_error),   // 输入: 指定打印错误
		
		// 状态输出 (matrix_selector_display不直接连接storage和printer)
		// 这些信号通过print_specified_dim_matrix模块传递
		.read_en(),                            // 未使用
		.rd_col(),                             // 未使用
		.rd_row(),                             // 未使用
		.rd_mat_index(),                       // 未使用
		.rd_data_flow(200'd0),                 // 未使用
		.rd_ready(1'b0),                       // 未使用
		
		.matrix_print_start(),                 // 未使用
		.matrix_flat(),                        // 未使用
		.matrix_print_busy(1'b0),              // 未使用
		.matrix_print_done(1'b0),              // 未使用
		
		// 状态输出
		.error(display_error),                   // 输出: 错误状态
		.done(display_done),                     // 输出: 完成状态
		.selected_matrix_id(selected_matrix_id)  // 输出: 选中的矩阵ID
	);

	// Print Specified Dimension Matrix 打印指定维度矩阵模块
	// 数据流: spec_dim -> info_table查询 -> matrix_storage读取 -> matrix_printer打印
	print_specified_dim_matrix u_print_specified_dim_matrix (
		.clk(clk),
		.rst_n(rst_n),
		.start(print_spec_start),             // 输入: 启动打印
		.busy(print_spec_busy),               // 输出: 模块忙状态
		.done(print_spec_done),               // 输出: 打印完成
		.error(print_spec_error),             // 输出: 错误 (未找到匹配矩阵)
		
		// 输入的目标维度
		.dim_m(spec_dim_m),                   // 输入: 目标矩阵行数
		.dim_n(spec_dim_n),                   // 输入: 目标矩阵列数
		
		// 连接到matrix_storage
		.info_table(info_table),              // 输入: 矩阵信息表 (用于查询)
		.read_en(store_read_en),              // 输出: 读使能
		.dimM(store_rd_col),                  // 输出: 读取的矩阵列数
		.dimN(store_rd_row),                  // 输出: 读取的矩阵行数
		.mat_index(store_rd_mat_index),       // 输出: 读取的矩阵索引
		.rd_ready(store_rd_ready),            // 输入: 读取就绪
		.rd_data_flow(store_rd_data_flow),    // 输入: 读取的矩阵数据
		
		// 连接到matrix_printer
		.matrix_printer_start(matrix_print_start), // 输出: 启动矩阵打印
		.matrix_printer_done(matrix_print_done),   // 输入: 矩阵打印完成
		.matrix_flat(matrix_flat),                 // 输出: 矩阵数据
		.use_crlf(1'b1),                           // 使用回车换行
		
		// UART输出
		.uart_tx_busy(uart_tx_busy),          // 输入: UART忙状态
		.uart_tx_en(uart_tx_en_spec),         // 输出: UART发送使能
		.uart_tx_data(uart_tx_data_spec)      // 输出: UART发送数据
	);

	// Matrix Printer for Display 显示模式的矩阵打印器
	// 数据流: matrix_flat -> matrix_printer -> UART TX
	// 注意: matrix_dim_m/n 需要从matrix_flat中获取或从spec_dim传递
	matrix_printer u_print_for_display (
		.clk(clk),
		.rst_n(rst_n),
		.start(matrix_print_start),       // 输入: 启动打印
		.matrix_flat(matrix_flat),        // 输入: 矩阵数据
		.dimM(spec_dim_m),                // 输入: 矩阵行数 (使用用户输入的维度)
		.dimN(spec_dim_n),                // 输入: 矩阵列数
		.use_crlf(1'b1),                  // 使用回车换行
		.tx_start(uart_tx_en_spec),       // 输出: UART发送使能
		.tx_data(uart_tx_data_spec),      // 输出: UART发送数据
		.tx_busy(uart_tx_busy),           // 输入: UART忙状态
		.done(matrix_print_done)          // 输出: 打印完成
	);

	// Display模式UART输出多路复用
	// 根据当前是打印表格还是打印矩阵选择输出源
	assign uart_tx_en_display = print_busy_table ? uart_tx_en_table : uart_tx_en_spec;
	assign uart_tx_data_display = print_busy_table ? uart_tx_data_table : uart_tx_data_spec;

endmodule
