// ========================================
// ϵͳ����ģ�� sys_top
// ========================================
// ����: ��������ϵͳ���㼯��
// 
// ��Ҫ����ģ��:
// 1. ��������ģʽ: UART���� -> ���� -> �洢 -> ��ӡ����
// 2. ����ģʽ: ������ɾ��� -> �洢 -> ��ӡ
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
	input wire btn_confirm,
	input wire btn_exit,
	input wire btn_countdown,  // 新增倒计时按钮
	input wire uart_rxd,
	output wire uart_txd,
	output reg [7:0] ld2,
	output reg [7:0] led,
	output reg [7:0] dk1_segments,
	output reg [7:0] dk2_segments,
	output reg [7:0] dk_digit_select
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
	

    // mode????
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

	// --- LED״ָ̬ʾ�ƿ��� ---
	reg led0_on;
	reg [24:0] led0_cnt; // 0.5����˸��������50MHzʱ����0.5s=25_000_000
	reg led1_on; // gen_done״ָ̬ʾ
	reg [24:0] led1_cnt;
	reg led2_on; // gen_error״ָ̬ʾ
	reg [24:0] led2_cnt;
	reg led3_on; // gen_valid״ָ̬ʾ
	reg [24:0] led3_cnt;
	wire [7:0] ld2_wire;
	assign ld2_wire = {7'd0, led0_on};


	// ??????????????��???????????
	assign seg_data0 = 8'd0;
	assign seg_data1 = 8'd0;
	assign seg_sel0 = 8'd0;
	assign seg_sel1 = 8'd0;

	// --- LED0��˸���� (�洢ָʾ) ---
	always @(posedge clk or negedge rst_n) begin
	    if (!rst_n) begin
	        led0_on <= 1'b0;
	        led0_cnt <= 25'd0;
	    end else if (store_write_en) begin
	        led0_on <= 1'b1;
	        led0_cnt <= 25'd0;
	    end else if (led0_on) begin
	        if (led0_cnt < 25'd24_999_999) begin
	            led0_cnt <= led0_cnt + 1'b1;
	        end else begin
	            led0_on <= 1'b0;
	        end
	    end
	end

	// --- LED1��˸���� (�������ָʾ) ---
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

	// --- LED2��˸���� (���ɴ���ָʾ) ---
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

	// --- LED3��˸���� (������Чָʾ) ---
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

    // LD2���鸳ֵ (�ۺ�״̬��ʾ)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ld2 <= 8'd0;
        end else begin
            ld2[0] <= ld2_wire[0];  // ����洢ָʾ
            ld2[1] <= led1_on;      // gen_done�������
            ld2[2] <= led2_on;      // gen_error���ɴ���
            ld2[3] <= led3_on;      // gen_valid������Ч
            ld2[4] <= ~debug_state[0]; // print_table״̬������
            ld2[5] <= ~debug_state[1];
            ld2[6] <= ~debug_state[2];
            ld2[7] <= ~debug_state[3];
        end
    end

	// --- UART Parser ���ڽ����� ---
	// ����: ����UART���յľ������ݸ�ʽ
	// ����: uart_rx_data, uart_rx_done, data_input_mode_en
	// ���: parsed_m, parsed_n, parsed_matrix_flat, parse_done, parse_error
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
	// --- Matrix Store ����洢�����߼� ---
	// ����: �����������ɵľ���д��洢ģ��
	// ��������: parse_done (�������) �� gen_valid (������Ч)
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
				store_mat_col <= parsed_m;
				store_mat_row <= parsed_n;
				store_data_flow <= parsed_matrix_flat;
			end else if (gen_valid & ~gen_valid_d) begin
				store_write_en <= 1'b1;
				store_mat_col <= gen_m;
				store_mat_row <= gen_n;
				store_data_flow <= gen_flow;
			end
		end
	end

	// --- Matrix Storage ����洢ģ�� ---
	// ���ڴ洢���������ɵľ�������
	wire [49:0] info_table;        // ������Ϣ�� (ÿ������5�ֽ�:�С��С�ID��)
	wire [7:0] total_count;        // �Ѵ洢��������
	
	// --- 存储读取仲裁: print_specified_dim_matrix 和 matrix_selector_display 共享 ---
	// print_specified_dim_matrix 的读取信号
	wire spec_read_en;
	wire [2:0] spec_rd_col;
	wire [2:0] spec_rd_row;
	wire [1:0] spec_rd_mat_index;
	
	// matrix_selector_display 的读取信号 (前向声明)
	wire selector_read_en;
	wire [2:0] selector_rd_col;
	wire [2:0] selector_rd_row;
	wire [1:0] selector_rd_mat_index;
	
	// 仲裁后的存储读取信号 (selector 优先，因为它在 spec 完成后才工作)
	wire store_read_en = selector_read_en | spec_read_en;
	wire [2:0] store_rd_col = selector_read_en ? selector_rd_col : spec_rd_col;
	wire [2:0] store_rd_row = selector_read_en ? selector_rd_row : spec_rd_row;
	wire [1:0] store_rd_mat_index = selector_read_en ? selector_rd_mat_index : spec_rd_mat_index;
	
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
		// ״̬���
		.total_count(total_count),
		.info_table(info_table)
	);
	
	// --- Generate Mode ��������ģʽ ---
	// ����: ����UART����Ĳ���������ɾ���
	// ����UART RX��������
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

	// --- Print��ӡ���� UART TX��·���� ---
	// Parseģʽ��UART����ź�
	wire uart_tx_en_parse;
	wire [7:0] uart_tx_data_parse;
	wire print_done_parse;

	// Generateģʽ��UART����ź�
	wire uart_tx_en_gen;
	wire [7:0] uart_tx_data_gen;
	wire print_done_gen;

	// Displayģʽ UART ����分三路：表格、计数头、矩阵正文
	wire uart_tx_en_display;
	wire [7:0] uart_tx_data_display;
	// 指定规格计数头 UART（来自 print_specified_dim_matrix）
	wire uart_tx_en_spec_cnt;
	wire [7:0] uart_tx_data_spec_cnt;
	// 指定规格矩阵正文 UART（来自 matrix_printer）
	wire uart_tx_en_spec_mat;
	wire [7:0] uart_tx_data_spec_mat;

	// UART TX��·������ - ���ݵ�ǰģʽѡ�����Դ
	always @(*) begin
		if (data_input_mode_en) begin
			// ��������ģʽ - ���������ľ���
			uart_tx_en = uart_tx_en_parse;
			uart_tx_data = uart_tx_data_parse;
		end else if (generate_mode_en) begin
			// ����ģʽ - ������ɵľ���
			uart_tx_en = uart_tx_en_gen;
			uart_tx_data = uart_tx_data_gen;
		end else if (display_mode_en) begin
			// 显示模式 - 优先表格 -> 计数头 -> 矩阵正文 -> 用户选择的矩阵
			if (print_busy_table || print_table_start) begin
				uart_tx_en   = uart_tx_en_table;
				uart_tx_data = uart_tx_data_table;
			end else if (uart_tx_en_spec_cnt) begin
				// 计数头（三字节）优先于矩阵正文
				uart_tx_en   = uart_tx_en_spec_cnt;
				uart_tx_data = uart_tx_data_spec_cnt;
			end else if (uart_tx_en_spec_mat) begin
				// spec模块的矩阵打印
				uart_tx_en   = uart_tx_en_spec_mat;
				uart_tx_data = uart_tx_data_spec_mat;
			end else begin
				// 用户选择矩阵的打印 (selector)
				uart_tx_en   = uart_tx_en_selector;
				uart_tx_data = uart_tx_data_selector;
			end
		end else begin
			uart_tx_en = 1'b0;
			uart_tx_data = 8'd0;
		end
	end

	// --- Matrix Printer for Parse ����ģʽ�����ӡ ---
	// ������: uart_parser -> parsed_matrix_flat -> matrix_printer -> UART TX
	matrix_printer u_print_for_parse (
		.clk(clk),
		.rst_n(rst_n),
		.start(parse_done),              // �������ʱ������ӡ
		.matrix_flat(parsed_matrix_flat), // ����: ������ľ�������
		.dimM(parsed_m),                 // ����: ��������
		.dimN(parsed_n),                 // ����: ��������
		.use_crlf(1'b1),                 // ʹ�ûس�����
		.tx_start(uart_tx_en_parse),     // ���: UART����ʹ��
		.tx_data(uart_tx_data_parse),    // ���: UART��������
		.tx_busy(uart_tx_busy),          // ����: UARTæ״̬
		.done(print_done_parse)          // ���: ��ӡ���
	);
	
    // --- Matrix Printer for Generate ����ģʽ�����ӡ ---
    // ������: generate_mode -> gen_flow -> matrix_printer -> UART TX
	matrix_printer u_print_for_generate (
		.clk(clk),
		.rst_n(rst_n),
		.start(gen_valid),            // ������Чʱ������ӡ
		.matrix_flat(gen_flow),       // ����: ���ɵľ�������
		.dimM(gen_m),                 // ����: ���ɵľ�������
		.dimN(gen_n),                 // ����: ���ɵľ�������
		.use_crlf(1'b1),              // ʹ�ûس�����
		.tx_start(uart_tx_en_gen),    // ���: UART����ʹ��
		.tx_data(uart_tx_data_gen),   // ���: UART��������
		.tx_busy(uart_tx_busy),       // ����: UARTæ״̬
		.done(print_done_gen)         // ���: ��ӡ���
	);
	
	// ========== Display Mode ��ʾģʽ ==========
	// ������: display_mode_en -> matrix_selector_display -> print_table �� print_specified_dim_matrix
	//        -> matrix_storage (��ȡ) -> matrix_printer -> UART TX
	
	// --- Print Table ��ӡ�����ź� ---
	wire uart_tx_en_table;           // �����ӡUARTʹ��
	wire [7:0] uart_tx_data_table;   // �����ӡUART����
	wire print_busy_table;           // �����ӡæ״̬
	wire print_done_table;           // �����ӡ���
	wire print_table_start;          // �����ӡ�����ź�
	wire [3:0] debug_state;          // ����״̬ (����LED��ʾ)
	
	// Print Table ģ�� - ��ӡ������Ϣ��
	// ������: info_table -> print_table -> UART TX
	print_table u_print_table (
		.clk(clk),
		.rst_n(rst_n),
		.start(print_table_start),         // ����: ������ӡ����
		.uart_tx_busy(uart_tx_busy),       // ����: UARTæ״̬
		.uart_tx_en(uart_tx_en_table),     // ���: UART����ʹ��
		.uart_tx_data(uart_tx_data_table), // ���: UART��������
		.info_table(info_table),           // ����: ������Ϣ��
		.cnt(total_count),                 // ����: ��������
		.busy(print_busy_table),           // ���: ģ��æ״̬
		.done(print_done_table),           // ���: ��ӡ���
		.current_state(debug_state)        // ���: ��ǰ״̬
	);

	// --- Print Specified Matrix ��ӡָ�������ź� ---
	wire print_spec_start;               // ������ӡָ������
	wire [2:0] spec_dim_m, spec_dim_n;   // �û������Ŀ�����ά��
	wire print_spec_busy;                // ��ӡָ������æ״̬
	wire print_spec_done;                // ��ӡָ���������
	wire print_spec_error;               // ��ӡָ���������
	
	// Matrix Printer for Display ��ʾģʽ�����ӡ�ź�
	wire matrix_print_start;             // ���������ӡ
	wire [199:0] matrix_flat;            // Ҫ��ӡ�ľ������� (����print_specified_dim_matrix)
	// ����ά��ֱ��ʹ��spec_dim (��Ϊprint_specified_dim_matrix��ȷ����ѯ���ľ���ά����spec_dimƥ��)
	// wire [2:0] matrix_dim_m, matrix_dim_n; // ����Ҫ������wire��ֱ��ʹ��spec_dim_m/n
	wire matrix_print_busy;              // �����ӡæ״̬
	wire matrix_print_done;              // �����ӡ���
	wire uart_tx_en_spec;                // ָ�������ӡUARTʹ�� (Ψһ��UART���Դ)
	wire [7:0] uart_tx_data_spec;        // ָ�������ӡUART���� (Ψһ��UART���Դ)
	
	// Displayģʽ״̬�ź�
	wire display_error;                  // ��ʾģʽ����
	wire display_done;                   // ��ʾģʽ���
	wire [1:0] selected_matrix_id;       // ѡ�еľ���ID

	// --- matrix_selector_display 的矩阵打印接口 ---
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
		
		// ��print_tableģ�������
		.print_table_start(print_table_start), // ���: ������ӡ����
		.print_table_busy(print_busy_table),   // ����: �����ӡæ
		.print_table_done(print_done_table),   // ����: �����ӡ���
		
		// UART���� - �����û������ά��
		.uart_input_data(uart_rx_data),        // ����: UART��������
		.uart_input_valid(uart_rx_done),       // ����: UART������Ч
		
		// ��print_specified_dim_matrixģ�������
		.print_spec_start(print_spec_start),   // ���: ������ӡָ������
		.spec_dim_m(spec_dim_m),               // ���: Ŀ���������
		.spec_dim_n(spec_dim_n),               // ���: Ŀ���������
		.print_spec_busy(print_spec_busy),     // ����: ָ����ӡæ
		.print_spec_done(print_spec_done),     // ����: ָ����ӡ���
		.print_spec_error(print_spec_error),   // ����: ָ����ӡ����
		
		// 与 matrix_storage 通信：读取用户选择的矩阵
		.read_en(selector_read_en),
		.rd_col(selector_rd_col),
		.rd_row(selector_rd_row),
		.rd_mat_index(selector_rd_mat_index),
		.rd_data_flow(store_rd_data_flow),
		.rd_ready(store_rd_ready),
		
		// 与 matrix_printer 通信：打印选中的矩阵
		.matrix_print_start(selector_print_start),
		.matrix_flat(selector_matrix_flat),
		.matrix_print_busy(selector_print_busy),
		.matrix_print_done(selector_print_done),
		
		// ״̬���
		.error(display_error),                   // ���: ����״̬
		.done(display_done),                     // ���: ���״̬
		.selected_matrix_id(selected_matrix_id)  // ���: ѡ�еľ���ID
	);

	// Print Specified Dimension Matrix 打印指定维度矩阵模块
	// 数据流: spec_dim -> info_table 查询 -> matrix_storage 读取 -> 先发计数头 -> 触发 matrix_printer 打印
	print_specified_dim_matrix u_print_specified_dim_matrix (
		.clk(clk),
		.rst_n(rst_n),
		.start(print_spec_start),             // ����: ������ӡ
		.busy(print_spec_busy),               // ���: ģ��æ״̬
		.done(print_spec_done),               // ���: ��ӡ���
		.error(print_spec_error),             // ���: ���� (δ�ҵ�ƥ�����)
		
		// �����Ŀ��ά��
		.dim_m(spec_dim_m),                   // ����: Ŀ���������
		.dim_n(spec_dim_n),                   // ����: Ŀ���������
		
		// ���ӵ�matrix_storage
		.info_table(info_table),              // ����: ������Ϣ�� (���ڲ�ѯ)
		.read_en(spec_read_en),               // ���: ��ʹ��
		.dimM(spec_rd_col),                   // ���: �ȡľ��������
		.dimN(spec_rd_row),                   // ���: �ȡľ��������
		.mat_index(spec_rd_mat_index),        // ���: �ȡľ��������
		.rd_ready(store_rd_ready),            // ����: ��ȡ����
		.rd_data_flow(store_rd_data_flow),    // ����: ��ȡ�ľ�������
		
		// ���ӵ�matrix_printer (ͨ����Щ�źŴ�������)
		.matrix_printer_start(matrix_print_start), // ���: ���������ӡ
		.matrix_printer_done(matrix_print_done),   // ����: �����ӡ���
		.matrix_flat(matrix_flat),                 // ���: �������ݴ��ݸ�printer
		.use_crlf(1'b1),                          // ʹ�ûس�����
        
		// UART输出（计数头）
		.uart_tx_busy(uart_tx_busy),
		.uart_tx_en(uart_tx_en_spec_cnt),
		.uart_tx_data(uart_tx_data_spec_cnt)
	);

	// Matrix Printer for Display 显示模式的矩阵打印器（正文）
	// 数据流: print_specified_dim_matrix -> matrix_flat -> matrix_printer -> UART TX
	matrix_printer u_print_for_display (
		.clk(clk),
		.rst_n(rst_n),
		.start(matrix_print_start),       // ����: ����print_specified_dim_matrix�������ź�
		.matrix_flat(matrix_flat),        // ����: ����print_specified_dim_matrix�ľ�������
		.dimM(spec_dim_m),                // ����: �������� (ʹ���û������ά��)
		.dimN(spec_dim_n),                // ����: �������� (ʹ���û������ά��)
		.use_crlf(1'b1),                  // ʹ�ûس�����
		.tx_start(uart_tx_en_spec_mat),   // ���: UART����ʹ�� (矩阵正文)
		.tx_data(uart_tx_data_spec_mat),  // ���: UART�������� (矩阵正文)
		.tx_busy(uart_tx_busy),           // ����: UARTæ״̬
		.done(matrix_print_done)          // ���: ��ӡ��ɣ�������print_specified_dim_matrix
	);
	// --- Matrix Printer for Selector: matrix_selector_display 用户选择矩阵打印 ---
	matrix_printer u_print_for_selector (
		.clk(clk),
		.rst_n(rst_n),
		.start(selector_print_start),
		.matrix_flat(selector_matrix_flat),
		.dimM(spec_dim_m),                // 使用用户输入的维度
		.dimN(spec_dim_n),
		.use_crlf(1'b1),
		.tx_start(uart_tx_en_selector),
		.tx_data(uart_tx_data_selector),
		.tx_busy(uart_tx_busy),
		.done(selector_print_done)
	);
	
	// selector_print_busy 根据打印器状态生成
	assign selector_print_busy = selector_print_start | (~selector_print_done & (selector_print_start | uart_tx_en_selector));
	// Display模式 UART 选择信号（不再使用二选一固定选择）
	// 由上方 always 块统一选择输出到 uart_tx

endmodule
