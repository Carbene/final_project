// ========================================
// ϵͳ����ģ�� sys_top
// ========================================
// ����: ��������ϵͳ���㼯��
// 
// ��Ҫ����ģ��:
// 1. ��������ģʽ: UART���� -> ���� -> �洢 -> ��ӡ����
// 2. ����ģʽ: ������ɾ���????????? -> �洢 -> ��ӡ
// 3. ��ʾģʽ: ��ѯ����ʾ�Ѵ洢�ľ���
// 4. ����ģʽ: �������� (��ʵ��)
//
// ������:
//   UART RX -> Parser/Generator -> Matrix Storage -> Display/Calculate
//                                                  -> UART TX
// ========================================

module sys_top(
	input wire clk,
	input wire rst_n,
	input wire [7:0] command,
	input wire [7:0] scalar_command,
	input wire btn_confirm,
	input wire btn_countdown,  // 新增倒计时按�?????????
	input wire uart_rxd,
	output wire uart_txd,
	output wire [7:0] led,
	output wire [7:0] dk1_segments,
	output wire [7:0] dk2_segments,
	output wire [7:0] dk_digit_select
);


	// --- �������� Button Debouncer ---
	wire btn_confirm_db;
	btn_debouncer u_btn_debouncer(
		.clk(clk),
		.rst_n(rst_n),
		.btn_in(btn_confirm),
		.btn_out(),
        .pulse(btn_confirm_db)
	);
    // --- UART RX ���ڽ��� ---
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
	wire uart_tx_busy;

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
	wire conv_mode_en;
	wire settings_mode_en;
	

    assign led={(parse_error|| gen_error || display_error || calc_error || setting_error), 1'b0,
	data_input_mode_en,generate_mode_en,display_mode_en,calculation_mode_en,conv_mode_en,settings_mode_en};
    assign dk_digit_select = {dk1_digit_select,dk2_sel};

	Central_Controller u_ctrl(
		.clk(clk),
		.rst_n(rst_n),
		.command(command[2:0]),
		.btn_confirm(btn_confirm_db),
		
		.data_input_mode_en(data_input_mode_en),
		
		.generate_mode_en(generate_mode_en),
		
		.display_mode_en(display_mode_en),
		
		.calculation_mode_en(calculation_mode_en),

		.conv_mode_en(conv_mode_en),

		.settings_mode_en(settings_mode_en)
	);

	// --- UART Parser ���ڽ����� ---
	// ����: ����UART���յľ������ݸ�ʽ
	// ����: uart_rx_data, uart_rx_done, data_input_mode_en
	// ���?????????: parsed_m, parsed_n, parsed_matrix_flat, parse_done, parse_error
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

	// --- Parse print handshake to ensure reliable start ---
	// Detect rising edge of parse_done, hold a request until UART is idle,
	// then generate a one-cycle start pulse for the parse printer.
	reg parse_done_q;
	always @(posedge clk or negedge rst_n) begin
	    if (!rst_n) begin
	        parse_done_q <= 1'b0;
	    end else begin
	        parse_done_q <= parse_done;
	    end
	end

	reg parse_print_req;
	always @(posedge clk or negedge rst_n) begin
	    if (!rst_n) begin
	        parse_print_req <= 1'b0;
	    end else if (parse_done & ~parse_done_q) begin
	        // latch request on parse_done rising edge
	        parse_print_req <= 1'b1;
	    end else if (print_done_parse) begin
	        // clear when printing completes
	        parse_print_req <= 1'b0;
	    end
	end

	reg parse_print_start;
	always @(posedge clk or negedge rst_n) begin
	    if (!rst_n) begin
	        parse_print_start <= 1'b0;
	    end else if (parse_print_req && !uart_tx_busy && data_input_mode_en) begin
	        // issue a single-cycle start when UART is idle in input mode
	        parse_print_start <= 1'b1;
	    end else begin
	        parse_print_start <= 1'b0;
	    end
	end
	// --- Matrix Store ����洢�����߼�????????? ---
	// ����: �����������ɵľ���д��洢ģ��?????????
	// ��������: parse_done (�������?????????) �� gen_valid (������Ч)
	reg store_write_en;
	reg [2:0] store_mat_col;
	reg [2:0] store_mat_row;
	reg [199:0] store_data_flow;
	reg parse_done_d, gen_valid_d;
	always @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			store_write_en <= 1'b0;
			store_mat_col <= 3'd0;
			store_mat_row <= 3'd0;
			store_data_flow <= 200'd0;
			parse_done_d <= 1'b0;
			gen_valid_d <= 1'b0;
		end else begin
			// �߿�⣬��parse_done/gen_valid���������һ��д�����
			parse_done_d <= parse_done;
			gen_valid_d <= gen_valid;
			store_write_en <= 1'b0;
			if (parse_done & ~parse_done_d) begin
				store_write_en <= 1'b1;
				// m=row, n=col: write as (row=m, col=n)
				store_mat_row <= parsed_m;
				store_mat_col <= parsed_n;
				store_data_flow <= parsed_matrix_flat;
			end else if (gen_valid & ~gen_valid_d) begin
				store_write_en <= 1'b1;
				// m=row, n=col: write as (row=m, col=n)
				store_mat_row <= gen_m;
				store_mat_col <= gen_n;
				store_data_flow <= gen_flow;
			end
		end
	end

	// --- Matrix Storage ����洢ģ��????????? ---
	// ���ڴ洢���������ɵľ�������
	wire [49:0] info_table;        // ������Ϣ�� (ÿ������5�ֽ�:�С��С�ID��)
	wire [7:0] total_count;        // �Ѵ洢��������
	
	// --- 存储读取仲裁: print_specified_dim_matrix �????????? matrix_selector_display 共享 ---
	// print_specified_dim_matrix 的读取信�?????????
	wire spec_read_en;
	wire [2:0] spec_rd_col;
	wire [2:0] spec_rd_row;
	wire [1:0] spec_rd_mat_index;
	
	// matrix_selector_display 的读取信�????????? (前向声明)
	wire selector_read_en;
	wire [2:0] selector_rd_col;
	wire [2:0] selector_rd_row;
	wire [1:0] selector_rd_mat_index;
	
	// rand_sel_from_store 的读取信号（前向声明）
	wire rand_rd_en;
	wire [2:0] rand_rd_col;
	wire [2:0] rand_rd_row;
	wire [1:0] rand_rd_mat_index;
	
	// 仲裁后的存储读取信号 (优先级: rand > selector > spec)
	wire store_read_en = rand_rd_en | selector_read_en | spec_read_en;
	wire [2:0] store_rd_col = rand_rd_en ? rand_rd_col : (selector_read_en ? selector_rd_col : spec_rd_col);
	wire [2:0] store_rd_row = rand_rd_en ? rand_rd_row : (selector_read_en ? selector_rd_row : spec_rd_row);
	wire [1:0] store_rd_mat_index = rand_rd_en ? rand_rd_mat_index : (selector_read_en ? selector_rd_mat_index : spec_rd_mat_index);
	
	wire [199:0] store_rd_data_flow; // ��ȡ�ľ���������
	wire store_rd_ready;           // ��ȡ׼���ź�
	wire store_err_rd;             // ��ȡ�����ź�
	
	matrix_storage #(
		.DATAWIDTH(8),
		.MAXNUM(2),
		.PICTUREMATRIXSIZE(25)
	) u_store (
		.clk(clk),
		.rst_n(rst_n),
		// д�ӿ� - ���ӵ�parse��generateģ��
		.write_en(store_write_en),
		.mat_col(store_mat_col),
		.mat_row(store_mat_row),
		.data_flow(store_data_flow),
		// ���ӿ� - ���ӵ�displayģ��
		.read_en(store_read_en),
		.rd_col(store_rd_col),
		.rd_row(store_rd_row),
		.rd_mat_index(store_rd_mat_index),
		.rd_data_flow(store_rd_data_flow),
		.rd_ready(store_rd_ready),
		.err_rd(store_err_rd),
		// ״̬���?????????
		.total_count(total_count),
		.info_table(info_table)
	);
	
	// --- Generate Mode ��������ģʽ ---
	// ����: ����UART����Ĳ���������ɾ���
	wire [199:0] gen_flow;
	wire gen_done;
	wire gen_error;
	wire gen_valid;
	wire [2:0] gen_m, gen_n;
	generate_mode u_generate_operate(
		.clk(clk),
		.rst_n(rst_n),
		.start(generate_mode_en),
		.uart_data(uart_rx_data),
		.uart_data_valid(uart_rx_done),
		.gen_matrix_flat(gen_flow),
		.gen_m(gen_m),
		.gen_n(gen_n),
		.gen_done(gen_done),
		.gen_valid(gen_valid),
		.error(gen_error)
	);

	// --- Print��ӡ���� UART TX��·���� ---
	// Parseģʽ��UART����ź�?????????
	wire uart_tx_en_parse;
	wire [7:0] uart_tx_data_parse;
	wire print_done_parse;

	// Generateģʽ��UART����ź�?????????
	wire uart_tx_en_gen;
	wire [7:0] uart_tx_data_gen_out;
	wire print_done_gen;
	// 指定规格计数�????????? UART（来�????????? print_specified_dim_matrix�?????????
	wire uart_tx_en_spec_cnt;
	wire [7:0] uart_tx_data_spec_cnt;
	// 指定规格矩阵正文 UART（来�????????? matrix_printer�?????????
	wire uart_tx_en_spec_mat;
	wire [7:0] uart_tx_data_spec_mat;

	// UART TX��·������ - ���ݵ�ǰģʽѡ������?
	always @(*) begin
		if (data_input_mode_en) begin
			// ��������ģʽ - ���������ľ���
			uart_tx_en = uart_tx_en_parse;
			uart_tx_data = uart_tx_data_parse;
		end else if (generate_mode_en) begin
			// ����ģʽ - ������ɵľ���?????????
			uart_tx_en = uart_tx_en_gen;
			uart_tx_data = uart_tx_data_gen_out;
		end else if (display_mode_en) begin
			// 显示模式 - 优先表格 -> 计数�????????? -> 矩阵正文 -> 用户选择的矩�?????????
			if (print_busy_table || print_table_start) begin
				uart_tx_en   = uart_tx_en_table;
				uart_tx_data = uart_tx_data_table;
			end else if (uart_tx_en_spec_cnt) begin
				// 计数头（三字节）优先于矩阵正�?????????
				uart_tx_en   = uart_tx_en_spec_cnt;
				uart_tx_data = uart_tx_data_spec_cnt;
			end else if (uart_tx_en_spec_mat) begin
				// spec模块的矩阵打�?????????
				uart_tx_en   = uart_tx_en_spec_mat;
				uart_tx_data = uart_tx_data_spec_mat;
			end else if(uart_tx_en_selector) begin
				// 用户选择矩阵的打�????????? (selector)
				uart_tx_en   = uart_tx_en_selector;
				uart_tx_data = uart_tx_data_selector;
			end else begin
				uart_tx_en = 1'b0;
				uart_tx_data = 8'd0;
			end
		end else if (conv_mode_en) begin
			// 卷积模式 - 优先矩阵打印，否则发送控制信�????????
			if (conv_print_enable) begin
				// conv模块的矩阵打�?????????
				uart_tx_en   = conv_printer_tx_start;
				uart_tx_data = conv_printer_tx_data;
			end else begin
				// conv模块的控制信息输出（周期数）
				uart_tx_en   = conv_uart_tx_en;
				uart_tx_data = conv_uart_tx_data;
			end		end else if (calculation_mode_en) begin
				if(is_result_mode) begin
			// 计算模式 - 结果打印器输�??????
			uart_tx_en   = result_printer_tx_start;
			uart_tx_data = result_printer_tx_data;		
			end else begin
			uart_tx_en = uart_tx_en_calculator;
			uart_tx_data = uart_tx_data_calculator;
			end end else begin
			uart_tx_en = 1'b0;
			uart_tx_data = 8'd0;
		end
	end
	// --- Matrix Printer for Parse ����ģʽ������? ---
	// ������: uart_parser -> parsed_matrix_flat -> matrix_printer -> UART TX
	matrix_printer u_print_for_parse (
		.clk(clk),
		.rst_n(rst_n),
		.start(parse_print_start),       // reliable start after UART idle
		.matrix_flat(parsed_matrix_flat), // ����: ������ľ�������?????????
		.dimM(parsed_m),                 // ����: ��������
		.dimN(parsed_n),                 // ����: ��������
		.use_crlf(1'b1),                 // ʹ�ûس�����
		.tx_start(uart_tx_en_parse),     // ���?????????: UART����ʹ��
		.tx_data(uart_tx_data_parse),    // ���?????????: UART��������
		.tx_busy(uart_tx_busy),          // ����: UARTæ״̬
		.done(print_done_parse)          // ���?????????: ��ӡ���?????????
	);
	
    // --- Matrix Printer for Generate ����ģʽ������? ---
    // ������: generate_mode -> gen_flow -> matrix_printer -> UART TX
	matrix_printer u_print_for_generate (
		.clk(clk),
		.rst_n(rst_n),
		.start(gen_valid),            // ������Чʱ������ӡ
		.matrix_flat(gen_flow),       // ����: ���ɵľ�������
		.dimM(gen_m),                 // ����: ���ɵľ�������
		.dimN(gen_n),                 // ����: ���ɵľ�������
		.use_crlf(1'b1),              // ʹ�ûس�����
		.tx_start(uart_tx_en_gen),        // ���?????????: UART����ʹ��
		.tx_data(uart_tx_data_gen_out),   // ���?????????: UART��������
		.tx_busy(uart_tx_busy),           // ����: UARTæ״̬
		.done(print_done_gen)             // ���?????????: ��ӡ���?????????
	);
	
	// ========== Display Mode ��ʾģʽ ==========
	// ������: display_mode_en -> matrix_selector_display -> print_table �� print_specified_dim_matrix
	//        -> matrix_storage (��ȡ) -> matrix_printer -> UART TX
	
	// --- Print Table ��ӡ�����ź� ---
	wire uart_tx_en_table;           // �����ӡUARTʹ��
	wire [7:0] uart_tx_data_table;   // �����ӡUART����
	wire print_busy_table;           // �����ӡæ״�?
	wire print_done_table;           // �����ӡ���
	wire print_table_start;          // �����ӡ�����ź�?????????
	wire [3:0] debug_state;          // ����״̬ (����LED��ʾ)
	
	// Print Table ģ�� - ��ӡ������Ϣ��
	// ������: info_table -> print_table -> UART TX
	print_table u_print_table (
		.clk(clk),
		.rst_n(rst_n),
		.start(print_table_start),         // ����: ������ӡ����
		.uart_tx_busy(uart_tx_busy),       // ����: UARTæ״̬
		.uart_tx_en(uart_tx_en_table),     // ���?????????: UART����ʹ��
		.uart_tx_data(uart_tx_data_table), // ���?????????: UART��������
		.info_table(info_table),           // ����: ������Ϣ��
		.cnt(total_count),                 // ����: ��������
		.busy(print_busy_table),           // ���?????????: ģ��æ״̬
		.done(print_done_table),           // ���?????????: ��ӡ���?????????
		.current_state(debug_state)        // ���?????????: ��ǰ״̬
	);

	// --- Print Specified Matrix ��ӡָ�������ź� ---
	wire print_spec_start;               // ������ӡָ������
	wire [2:0] spec_dim_m, spec_dim_n;   // �û������Ŀ�����ά��
	wire print_spec_busy;                // ��ӡָ������æ״̬
	wire print_spec_done;                // ��ӡָ���������?????????
	wire print_spec_error;               // ��ӡָ���������?????????
	
	// Matrix Printer for Display ��ʾģʽ�����ӡ�ź�?????????
	wire matrix_print_start;             // ����������?
	wire [199:0] matrix_flat;            // Ҫ��ӡ�ľ������� (����print_specified_dim_matrix)
	// ����ά��ֱ��ʹ��spec_dim (��Ϊprint_specified_dim_matrix��ȷ����ѯ���ľ���ά����spec_dimƥ��)
	// wire [2:0] matrix_dim_m, matrix_dim_n; // ����Ҫ������wire��ֱ��ʹ��spec_dim_m/n
	wire matrix_print_busy;              // �����ӡæ״�?
	wire matrix_print_done;              // �����ӡ���
	wire uart_tx_en_spec;                // ָ�������ӡUARTʹ�� (Ψһ��UART����?)
	wire [7:0] uart_tx_data_spec;        // ָ�������ӡUART���� (Ψһ��UART����?)
	
	// Displayģʽ״̬�ź�
	wire display_error;                  // ��ʾģʽ����
	wire display_done;                   // ��ʾģʽ���?????????
	wire [1:0] selected_matrix_id;       // ѡ�еľ���ID

	// --- matrix_selector_display 的矩阵打印接�????????? ---
	wire selector_print_start;
	wire [199:0] selector_matrix_flat;
	wire selector_print_busy;
	wire selector_print_done;
	wire uart_tx_en_selector;
	wire [7:0] uart_tx_data_selector;

	// Matrix Selector Display ����ѡ����ʾ������
	// ������: uart_rx -> matrix_selector_display -> (print_table �� print_specified_dim_matrix)
	matrix_selector_display u_matrix_selector_display (
		.clk(clk),
		.rst_n(rst_n),
		.start(display_mode_en),              // ����: ��ʾģʽʹ��
		
		// ��print_tableģ�������?????????
		.print_table_start(print_table_start), // ���?????????: ������ӡ����
		.print_table_busy(print_busy_table),   // ����: �����ӡ�?
		.print_table_done(print_done_table),   // ����: �����ӡ���
		
		// UART���� - �����û������ά��?????????
		.uart_input_data(uart_rx_data),        // ����: UART��������
		.uart_input_valid(uart_rx_done),       // ����: UART������Ч
		
		// ��print_specified_dim_matrixģ�������?????????
		.print_spec_start(print_spec_start),   // ���?????????: ������ӡָ������
		.spec_dim_m(spec_dim_m),               // ���?????????: Ŀ���������?????????
		.spec_dim_n(spec_dim_n),               // ���?????????: Ŀ���������?????????
		.print_spec_busy(print_spec_busy),     // ����: ָ����ӡæ
		.print_spec_done(print_spec_done),     // ����: ָ����ӡ���?????????
		.print_spec_error(print_spec_error),   // ����: ָ����ӡ����
		
		// �????????? matrix_storage 通信：读取用户�?�择的矩�?????????
		.read_en(selector_read_en),
		.rd_col(selector_rd_col),
		.rd_row(selector_rd_row),
		.rd_mat_index(selector_rd_mat_index),
		.rd_data_flow(store_rd_data_flow),
		.rd_ready(store_rd_ready),
		
		// �????????? matrix_printer 通信：打印�?�中的矩�?????????
		.matrix_print_start(selector_print_start),
		.matrix_flat(selector_matrix_flat),
		.matrix_print_busy(selector_print_busy),
		.matrix_print_done(selector_print_done),
		
		
		// 状�?�输�?????
		.error(display_error),
		.done(display_done),
		.selected_matrix_id(selected_matrix_id)
	);

	// Print Specified Dimension Matrix 打印指定维度矩阵模块
	// 数据�?????????: spec_dim -> info_table 查询 -> matrix_storage 读取 -> 先发计数�????????? -> 触发 matrix_printer 打印
	print_specified_dim_matrix u_print_specified_dim_matrix (
		.clk(clk),
		.rst_n(rst_n),
		.start(print_spec_start),             // ����: ������ӡ
		.busy(print_spec_busy),               // ���?????????: ģ��æ״̬
		.done(print_spec_done),               // ���?????????: ��ӡ���?????????
		.error(print_spec_error),             // ���?????????: ���� (δ�ҵ�ƥ�����?????????)
		
		// �����Ŀ��ά��?????????
		.dim_m(spec_dim_m),                   // ����: Ŀ���������?????????
		.dim_n(spec_dim_n),                   // ����: Ŀ���������?????????
		
		// ���ӵ�matrix_storage
		.info_table(info_table),              // ����: ������Ϣ�� (���ڲ�ѯ)
		.read_en(spec_read_en),               // ���?????????: ��ʹ��
		// m=row, n=col: map to storage rd_row, rd_col respectively
		.dimM(spec_rd_row),                   // dimM (row=m) -> rd_row
		.dimN(spec_rd_col),                   // dimN (col=n) -> rd_col
		.mat_index(spec_rd_mat_index),        // ���?????????: �ȡľ��������?????????
		.rd_ready(store_rd_ready),            // ����: ��ȡ����
		.rd_data_flow(store_rd_data_flow),    // ����: ��ȡ�ľ�������
		
		// ���ӵ�matrix_printer (ͨ����Щ�źŴ�������)
		.matrix_printer_start(matrix_print_start), // ���?????????: ����������?
		.matrix_printer_done(matrix_print_done),   // ����: �����ӡ���
		.matrix_flat(matrix_flat),                 // ���?????????: �������ݴ��ݸ�printer
		.use_crlf(1'b1),                          // ʹ�ûس�����
        
		// UART输出（计数头�?????????
		.uart_tx_busy(uart_tx_busy),
		.uart_tx_en(uart_tx_en_spec_cnt),
		.uart_tx_data(uart_tx_data_spec_cnt)
	);

	// Matrix Printer for Display 显示模式的矩阵打印器（正文）
	// 数据�?????????: print_specified_dim_matrix -> matrix_flat -> matrix_printer -> UART TX
	matrix_printer u_print_for_display (
		.clk(clk),
		.rst_n(rst_n),
		.start(matrix_print_start),       // ����: ����print_specified_dim_matrix�������ź�
		.matrix_flat(matrix_flat),        // ����: ����print_specified_dim_matrix�ľ�������
		.dimM(spec_dim_m),                // ����: �������� (ʹ���û������ά��?????????)
		.dimN(spec_dim_n),                // ����: �������� (ʹ���û������ά��?????????)
		.use_crlf(1'b1),                  // ʹ�ûس�����
		.tx_start(uart_tx_en_spec_mat),   // ���?????????: UART����ʹ�� (矩阵正文)
		.tx_data(uart_tx_data_spec_mat),  // ���?????????: UART�������� (矩阵正文)
		.tx_busy(uart_tx_busy),           // ����: UARTæ״̬
		.done(matrix_print_done)          // ���?????????: ��ӡ��ɣ�������print_specified_dim_matrix
	);
	// --- Matrix Printer for Selector: matrix_selector_display 用户选择矩阵打印 ---
	matrix_printer u_print_for_selector (
		.clk(clk),
		.rst_n(rst_n),
		.start(selector_print_start),
		.matrix_flat(selector_matrix_flat),
		.dimM(spec_dim_m),                // 使用用户输入的维�?????????
		.dimN(spec_dim_n),
		.use_crlf(1'b1),
		.tx_start(uart_tx_en_selector),
		.tx_data(uart_tx_data_selector),
		.tx_busy(uart_tx_busy),
		.done(selector_print_done)
	);
	
	// selector_print_busy 根据打印器状态生�?????????
	assign selector_print_busy = selector_print_start | (~selector_print_done & (selector_print_start | uart_tx_en_selector));
	// Display模式 UART 选择信号（不再使用二选一固定选择�?????????
	// 由上�????????? always 块统�?????????选择输出�????????? uart_tx

	//卷积模块  
	wire conv_done;
	wire conv_busy;
	wire conv_print_enable;
	wire conv_print_done;
	wire conv_uart_tx_en;
	wire [7:0] conv_uart_tx_data;   // 修复：从1位改�????????8�????????
	wire [1279:0] conv_matrix_flat;
	
	convolution_engine u_convolution_engine (
	.clk(clk),
	.rst(~rst_n),  // 修复：convolution_engine使用高电平复位，�????????要取�????????
	.enable(conv_mode_en),
	.uart_rx_valid(uart_rx_done & conv_mode_en),  // 修复：只在卷积模式下接收UART数据
	.uart_rx_data(uart_rx_data),
	.done(conv_done),
	.busy(conv_busy),
	.print_enable(conv_print_enable),
	.matrix_data(conv_matrix_flat),
	.print_done(conv_print_done)
	//.uart_tx_en(conv_uart_tx_en),
	//.uart_tx_data(conv_uart_tx_data),
	//.uart_tx_busy(uart_tx_busy & conv_mode_en)
	);
	wire conv_printer_tx_start;
	wire [7:0] conv_printer_tx_data;  // 修复：从1位改�????????8�????????
	conv_matrix_printer u_conv_matrix_printer (
	.clk(clk),
	.rst_n(rst_n),
	.start(conv_print_enable & conv_mode_en),    // 修复：只在卷积模式下启动打印
	.matrix_flat(conv_matrix_flat),      // 80 * 16
	.tx_busy(uart_tx_busy),
	.tx_start(conv_printer_tx_start),           // drive uart_tx_en
	.tx_data(conv_printer_tx_data),            // drive uart_tx_data
	.done(conv_print_done) 
	);               // pulses high when all rows sent

	reg [199:0] matrix_selected [1:0];
	reg [2:0] m_selected [1:0];
	reg [2:0] n_selected [1:0];
	reg ptr;
	

	reg [3:0] calc_mode;
	wire [2:0] op_code = calc_mode[2:0];
	reg calc_start;

	reg [4:0] state, next_state;
	reg [7:0] scalr_input;
	wire [7:0] scalar_input = scalar_command;           // 临时：沿用command作为标量输入�?????
	wire scalar_valid = (scalar_input <= 8'd9);  // 只允�?????0~9

	localparam CALC_IDLE        = 5'd0;
	localparam CALC_WAIT_CONFIRM = 5'd1;
	localparam CALC_BRANCH       = 5'd2;
	localparam CALC_SCALAR_CONFIRM = 5'd3;
	localparam CALC_SCALAR_VALIDATE = 5'd5;
	localparam CALC_COMPUTE    = 5'd4;
	localparam RESULT_WAIT    = 5'd7;
	localparam RESULT_PRINT    = 5'd8;
	localparam ERROR_SCALAR          = 5'd9;
	localparam ERROR_MATRIX      = 5'd10;
	localparam DONE      = 5'd6;
	localparam CALC_RANDOM_SELECT = 5'd11;
	localparam CALC_RANDOM_WAIT = 5'd12;
	localparam CALC_RAND_ERROR = 5'd13;
	localparam CALC_PRINT_MATRIX1 = 5'd14;
	localparam CALC_PRINT_MATRIX1_WAIT = 5'd17;
	localparam CALC_PRINT_MATRIX2 = 5'd15;
	localparam CALC_PRINT_MATRIX2_WAIT = 5'd18;
	
	localparam OP_TRANSPOSE = 3'd0;
	localparam OP_SCALAR = 3'd1;
	localparam OP_ADD       = 3'd2;
	localparam OP_MULTIPLY  = 3'd3;
	reg is_result_mode;
	always @(posedge clk or negedge rst_n) begin
	    if (!rst_n) begin
	        state <= CALC_IDLE;
	    end else begin
	        state <= next_state;
	    end
	end
	always @(*) begin
	    next_state = state;
	    case (state)
	        CALC_IDLE: begin
	            if (calculation_mode_en) begin
					if(counting) begin
						next_state = CALC_COMPUTE;
					end else begin
	                next_state = CALC_WAIT_CONFIRM;
					end
	            end
	        end
	        CALC_WAIT_CONFIRM: begin
	            if(btn_confirm_db) begin
					next_state = CALC_BRANCH;
	            end
	        end
			CALC_BRANCH: begin
				if(calc_mode[3]) begin // 是否�????要标量输�????
					next_state = CALC_RANDOM_SELECT;
				end else begin
				if(op_code == OP_SCALAR) begin
					next_state = CALC_SCALAR_CONFIRM;
				end else begin
					next_state = CALC_COMPUTE;
				end
				end
			end

			CALC_RANDOM_SELECT: begin
				next_state = CALC_RANDOM_WAIT;
			end

			CALC_RANDOM_WAIT: begin
				if(rand_done) begin
					next_state = CALC_COMPUTE;
				end else if(rand_fail) begin
					next_state = CALC_RAND_ERROR;
				end
			end

			CALC_SCALAR_CONFIRM: begin
				if(btn_confirm_db) begin
					next_state = CALC_SCALAR_VALIDATE;
				end
			end

			CALC_SCALAR_VALIDATE: begin
				if(scalar_valid) begin
					next_state = CALC_COMPUTE;
				end else begin
					next_state = ERROR_SCALAR;
				end
			end

			CALC_COMPUTE: begin
				if(result_done) begin
					if(result_valid) begin
						next_state = RESULT_PRINT;
					end else begin
						next_state = ERROR_MATRIX;
					end
				end
			end

			RESULT_PRINT: begin
				if(result_printer_done) begin
					next_state = CALC_PRINT_MATRIX1;
				end
			end

			CALC_PRINT_MATRIX1: begin
				next_state = CALC_PRINT_MATRIX1_WAIT;
			end
			CALC_PRINT_MATRIX1_WAIT: begin
				if(calculator_print_done) begin
					case(op_code)
					OP_ADD, OP_MULTIPLY: begin
						next_state = CALC_PRINT_MATRIX2;
					end
					default: begin
						next_state = DONE;
					end
				endcase
				end
			end
			CALC_PRINT_MATRIX2: begin
				next_state = CALC_PRINT_MATRIX2_WAIT;
			end
			CALC_PRINT_MATRIX2_WAIT: begin
				if(calculator_print_done) begin
					next_state = DONE;
				end
			end
			ERROR_SCALAR: begin
				next_state = CALC_SCALAR_CONFIRM;
			end
			DONE: begin
				if(!calculation_mode_en) begin
					next_state = CALC_IDLE;
				end
			end

			ERROR_MATRIX: begin
				if(!calculation_mode_en) begin
					next_state = CALC_IDLE;
				end
			end

			CALC_RAND_ERROR: begin
				if(!calculation_mode_en) begin
					next_state = CALC_IDLE;
				end
			end

	        default: begin
	            next_state = CALC_IDLE;
	        end
	    endcase
	end
	reg calc_error;
	wire [399:0] result_flat;
        wire [2:0] result_m;
        wire [2:0] result_n;
            reg timer_start;
            wire timer_done;
            reg end_timer;
            wire [7:0] countdown_time;
            wire counting;
            wire [3:0] dk1_digit_select;
	always@(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			calc_start <= 1'b0;
			calc_mode <= 4'd0;
			scalar <= 8'd0;
			result_printer_start <= 1'b0;
			timer_start <= 1'b0;
			end_timer <= 1'b0;
			calculator_print_start <= 1'b0;
			calculator_matrix_flat <= 200'd0;
			is_result_mode <= 1'b0;
			calc_error <= 1'b0;
			rand_start <= 1'b0;
		end else begin
			// 默认脉冲信号清零，但 calc_mode �?????? scalar 保持锁存�??????
			calc_start <= 1'b0;
			result_printer_start <= 1'b0;
			timer_start <= 1'b0;  // 默认清零
			end_timer <= 1'b0;
			calculator_print_start <= 1'b0;
			rand_start <= 1'b0;
			is_result_mode <= 1'b0;
			calc_error <= 1'b0;
			
			// 检测状态转换，在进入错误状态时产生 timer_start 脉冲
			if ((state != ERROR_SCALAR && next_state == ERROR_SCALAR) || 
			    (state != ERROR_MATRIX && next_state == ERROR_MATRIX)) begin
				timer_start <= 1'b1;
			end
			
			if (display_done) begin
			ptr <= ~ptr;
			matrix_selected[ptr] <= selector_matrix_flat;
			m_selected[ptr] <= spec_dim_m;  // 用户输入的查询维度，应与实际矩阵匹配
			n_selected[ptr] <= spec_dim_n;
	    	end
			case (state)
				CALC_IDLE: begin
					// 进入计算模式时不清零 calc_mode，保持上次设�??????
				end
				CALC_WAIT_CONFIRM: begin
					if(btn_confirm_db) begin
						calc_mode <= command[7:4];  // 锁存操作�??????
					end
				end
				CALC_BRANCH: begin
					// calc_mode 已经锁存，不�??????要再设置
				end
				CALC_RANDOM_SELECT: begin
					rand_start <= 1'b1;
				end
				CALC_RANDOM_WAIT: begin
					if(rand_matrix1_valid) begin
						matrix_selected[0] <= rand_matrix1;
						m_selected[0] <= rand_matrix1_m;
						n_selected[0] <= rand_matrix1_n;
					end else if(rand_matrix2_valid) begin
						matrix_selected[1] <= rand_matrix2;
						m_selected[1] <= rand_matrix2_m;
						n_selected[1] <= rand_matrix2_n;
					end
					scalar <= rand_scalar_out; // 使用随机标量
				end
				CALC_RAND_ERROR: begin
					calc_error <= 1'b1;
				end
				CALC_SCALAR_VALIDATE: begin
					if(scalar_valid) begin
						scalar <= scalar_input;
					end
				end
				CALC_COMPUTE: begin
					calc_start <= 1'b1;
				end
				RESULT_PRINT: begin
					is_result_mode <= 1'b1;
					result_printer_start <= 1'b1;
				end
				CALC_PRINT_MATRIX1: begin
					calculator_print_start <= 1'b1;
					calculator_matrix_flat <= matrix_selected[0];
					calculator_dim_m <= m_selected[0];
					calculator_dim_n <= n_selected[0];
				end
				CALC_PRINT_MATRIX1_WAIT: begin
					// calculator_print_start 已在默认赋值中清零
				end
				CALC_PRINT_MATRIX2: begin
					calculator_print_start <= 1'b1;
					calculator_matrix_flat <= matrix_selected[1];
					calculator_dim_m <= m_selected[1];
					calculator_dim_n <= n_selected[1];
				end
				CALC_PRINT_MATRIX2_WAIT: begin
					// calculator_print_start 已在默认赋值中清零
				end
				ERROR_SCALAR: begin
					// timer_start 脉冲已在状态转换时产生
					calc_error <= 1'b1;
				end
				ERROR_MATRIX: begin
					// timer_start 脉冲已在状态转换时产生
				    calc_error <= 1'b1;
				end
				DONE: begin
				end_timer <= 1'b1;
				calc_error <= 1'b0;
				end


				default: begin
					// do nothing
				end
			endcase
		end
	end
	countdown_controller u_countdown_controller (
		.clk(clk),
		.rst_n(rst_n),
		.start(timer_start),
		.counting(counting),
		.done(timer_done),
		.end_timer(end_timer),
		.dk1_segments(dk1_segments),
		.dk_digit_select(dk1_digit_select),
		.countdown_time(countdown_time)
	);
	wire setting_error;
	setting_subsystem u_setting_subsystem (
		.clk(clk),
		.rst_n(rst_n),
		.uart_rx_done(uart_rx_done),
		.uart_rx_data(uart_rx_data),
		.enable(settings_mode_en),
		.param_value(countdown_time),
		.param_error(setting_error)
	);

	reg result_printer_start;
	wire result_printer_done;
	wire result_printer_tx_start;
    wire [7:0] result_printer_tx_data;

	matrix_printer16 u_matrix_printer16 (
	    .clk(clk),
	    .rst_n(rst_n),
	    .start(result_printer_start),
	    .dimM(result_m),
	    .dimN(result_n),
	    .matrix_flat(result_flat),
	    .use_crlf(1'b1),
	    .tx_start(result_printer_tx_start),
	    .tx_data(result_printer_tx_data),
	    .tx_busy(uart_tx_busy),
	    .done(result_printer_done)
	);

	wire result_done;
	wire result_valid;
	reg [7:0] scalar;
	wire result_busy;

	matrix_alu u_matrix_alu (
	    .clk(clk),
	    .rst_n(rst_n),
	    .op_code(op_code),
	    .start(calc_start),
	    .matrix_a_flat(matrix_selected[0]),
	    .m_a(m_selected[0]),
	    .n_a(n_selected[0]),
	    .matrix_b_flat(matrix_selected[1]),
	    .m_b(m_selected[1]),
	    .n_b(n_selected[1]),
	    .scalar(scalar), // 修复：使用正确的scalar变量
	    .result_flat(result_flat),
	    .result_m(result_m),
	    .result_n(result_n),
	    .done(result_done),
	    .valid(result_valid),
	    .busy(result_busy)
	);
	wire [3:0] dk2_sel;
	output_cal_mod u_output_cal_mod (
	.clk(clk),
	.rst_n(rst_n),
	.op_code(op_code),
	.dk2_segments(dk2_segments),
	.dk2_sel(dk2_sel)
	);
	reg rand_start;
	// rand_rd_en, rand_rd_col, rand_rd_row, rand_rd_mat_index 已在仲裁部分前向声明

	wire [199:0] rand_matrix1;
    wire [199:0] rand_matrix2;
	wire [2:0] rand_matrix1_m;
	wire [2:0] rand_matrix1_n;
	wire [2:0] rand_matrix2_m;
	wire [2:0] rand_matrix2_n;
    wire rand_matrix1_valid;
    wire rand_matrix2_valid;
    wire rand_done;
    wire rand_fail;
    wire [3:0] rand_scalar_out; // 0..9

	rand_sel_from_store u_rand_sel_from_store (
	.clk(clk),
	.rst_n(rst_n),
	.start(rand_start),
	.op_mode(op_code), // 00 transpose,01 scalarmul,10 add,11 mul
	.info_table(info_table), // �???? matrix_store 直接读取�???? 25 �???? 2bit 计数（count[24]..count[0])

	// matrix_store 读取接口
	.read_en(rand_rd_en),
	.rd_col(rand_rd_col),
	.rd_row(rand_rd_row),
	.rd_mat_index(rand_rd_mat_index),
	.rd_data_flow(store_rd_data_flow),  // 连接到storage的输出
	.rd_ready(store_rd_ready),           // 连接到storage的输出
	.err_rd(store_err_rd),

	// 输出矩阵与控制信�????
	.matrix1(rand_matrix1),
	.matrix2(rand_matrix2),
	.matrix1_valid(rand_matrix1_valid),
	.matrix2_valid(rand_matrix2_valid),
	.dim_m1(rand_matrix1_m),
	.dim_n1(rand_matrix1_n),
	.dim_m2(rand_matrix2_m),
	.dim_n2(rand_matrix2_n),
	.done(rand_done),
	.fail(rand_fail),
	.scalar_out(rand_scalar_out)
	);

	reg calculator_print_start;
	reg [199:0] calculator_matrix_flat;
	reg [2:0] calculator_dim_m;
	reg [2:0] calculator_dim_n;
	wire uart_tx_en_calculator;
	wire [7:0] uart_tx_data_calculator;
	wire calculator_print_done;
	matrix_printer u_print_for_calculator (
		.clk(clk),
		.rst_n(rst_n),
		.start(calculator_print_start),
		.matrix_flat(calculator_matrix_flat),
		.dimM(calculator_dim_m),                // 使用用户输入的维�?????????
		.dimN(calculator_dim_n),
		.use_crlf(1'b1),
		.tx_start(uart_tx_en_calculator),
		.tx_data(uart_tx_data_calculator),
		.tx_busy(uart_tx_busy),
		.done(calculator_print_done)
	);

endmodule