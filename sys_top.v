// ========================================
// ϵͳ����ģ�� sys_top
// ========================================
// ����: ��������ϵͳ���㼯��
// 
// ��Ҫ����ģ��:
// 1. ��������ģʽ: UART���� -> ���� -> �洢 -> ��ӡ����
// 2. ����ģʽ: ������ɾ���?? -> �洢 -> ��ӡ
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
	input wire btn_countdown,  // 新增倒计时按�??
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
	

    // mode????
    wire [7:0] led_wire;
    assign led_wire={2'b0,data_input_mode_en,generate_mode_en,display_mode_en,calculation_mode_en,conv_mode_en,settings_mode_en};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            led <= 8'd0;
            dk1_segments <= 8'hFF;    // 数码管默认全�?
            dk2_segments <= 8'hFF;
            dk_digit_select <= 8'h00; // 数码管位选默认不选中
        end
        else begin
            led <= led_wire;
            dk1_segments <= 8'hFF;    // 暂未使用
            dk2_segments <= 8'hFF;
            dk_digit_select <= 8'h00;
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
		
		.calculation_mode_en(calculation_mode_en),

		.conv_mode_en(conv_mode_en),

		.settings_mode_en(settings_mode_en)
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

	// --- LED1��˸���� (�������ָ�?) ---
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
            ld2[0] <= ld2_wire[0];  // ����洢ָ�?
            ld2[1] <= led1_on;      // gen_done�������??
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
	// ���??: parsed_m, parsed_n, parsed_matrix_flat, parse_done, parse_error
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
	// --- Matrix Store ����洢�����߼�?? ---
	// ����: �����������ɵľ���д��洢ģ��??
	// ��������: parse_done (�������??) �� gen_valid (������Ч)
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

	// --- Matrix Storage ����洢ģ��?? ---
	// ���ڴ洢���������ɵľ�������
	wire [49:0] info_table;        // ������Ϣ�� (ÿ������5�ֽ�:�С��С�ID��)
	wire [7:0] total_count;        // �Ѵ洢��������
	
	// --- 存储读取仲裁: print_specified_dim_matrix �?? matrix_selector_display 共享 ---
	// print_specified_dim_matrix 的读取信�??
	wire spec_read_en;
	wire [2:0] spec_rd_col;
	wire [2:0] spec_rd_row;
	wire [1:0] spec_rd_mat_index;
	
	// matrix_selector_display 的读取信�?? (前向声明)
	wire selector_read_en;
	wire [2:0] selector_rd_col;
	wire [2:0] selector_rd_row;
	wire [1:0] selector_rd_mat_index;
	
	// 仲裁后的存储读取信号 (selector 优先，因为它�?? spec 完成后才工作)
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
		// ״̬���??
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
	// Parseģʽ��UART����ź�??
	wire uart_tx_en_parse;
	wire [7:0] uart_tx_data_parse;
	wire print_done_parse;

	// Generateģʽ��UART����ź�??
	wire uart_tx_en_gen;
	wire [7:0] uart_tx_data_gen_out;
	wire print_done_gen;
	// 指定规格计数�?? UART（来�?? print_specified_dim_matrix�??
	wire uart_tx_en_spec_cnt;
	wire [7:0] uart_tx_data_spec_cnt;
	// 指定规格矩阵正文 UART（来�?? matrix_printer�??
	wire uart_tx_en_spec_mat;
	wire [7:0] uart_tx_data_spec_mat;

	// UART TX��·������ - ���ݵ�ǰģʽѡ������?
	always @(*) begin
		if (data_input_mode_en) begin
			// ��������ģʽ - ���������ľ���
			uart_tx_en = uart_tx_en_parse;
			uart_tx_data = uart_tx_data_parse;
		end else if (generate_mode_en) begin
			// ����ģʽ - ������ɵľ���??
			uart_tx_en = uart_tx_en_gen;
			uart_tx_data = uart_tx_data_gen_out;
		end else if (display_mode_en) begin
			// 显示模式 - 优先表格 -> 计数�?? -> 矩阵正文 -> 用户选择的矩�??
			if (print_busy_table || print_table_start) begin
				uart_tx_en   = uart_tx_en_table;
				uart_tx_data = uart_tx_data_table;
			end else if (uart_tx_en_spec_cnt) begin
				// 计数头（三字节）优先于矩阵正�??
				uart_tx_en   = uart_tx_en_spec_cnt;
				uart_tx_data = uart_tx_data_spec_cnt;
			end else if (uart_tx_en_spec_mat) begin
				// spec模块的矩阵打�??
				uart_tx_en   = uart_tx_en_spec_mat;
				uart_tx_data = uart_tx_data_spec_mat;
			end else if(uart_tx_en_selector) begin
				// 用户选择矩阵的打�?? (selector)
				uart_tx_en   = uart_tx_en_selector;
				uart_tx_data = uart_tx_data_selector;
			end else begin
				uart_tx_en = 1'b0;
				uart_tx_data = 8'd0;
			end
		end else if (conv_mode_en) begin
			// 卷积模式 - 优先矩阵打印，否则发送控制信�?
			if (conv_print_enable) begin
				// conv模块的矩阵打�??
				uart_tx_en   = conv_printer_tx_start;
				uart_tx_data = conv_printer_tx_data;
			end else begin
				// conv模块的控制信息输出（周期数）
				uart_tx_en   = conv_uart_tx_en;
				uart_tx_data = conv_uart_tx_data;
			end
		end else begin
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
		.matrix_flat(parsed_matrix_flat), // ����: ������ľ�������??
		.dimM(parsed_m),                 // ����: ��������
		.dimN(parsed_n),                 // ����: ��������
		.use_crlf(1'b1),                 // ʹ�ûس�����
		.tx_start(uart_tx_en_parse),     // ���??: UART����ʹ��
		.tx_data(uart_tx_data_parse),    // ���??: UART��������
		.tx_busy(uart_tx_busy),          // ����: UARTæ״̬
		.done(print_done_parse)          // ���??: ��ӡ���??
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
		.tx_start(uart_tx_en_gen),        // ���??: UART����ʹ��
		.tx_data(uart_tx_data_gen_out),   // ���??: UART��������
		.tx_busy(uart_tx_busy),           // ����: UARTæ״̬
		.done(print_done_gen)             // ���??: ��ӡ���??
	);
	
	// ========== Display Mode ��ʾģʽ ==========
	// ������: display_mode_en -> matrix_selector_display -> print_table �� print_specified_dim_matrix
	//        -> matrix_storage (��ȡ) -> matrix_printer -> UART TX
	
	// --- Print Table ��ӡ�����ź� ---
	wire uart_tx_en_table;           // �����ӡUARTʹ��
	wire [7:0] uart_tx_data_table;   // �����ӡUART����
	wire print_busy_table;           // �����ӡæ״�?
	wire print_done_table;           // �����ӡ���
	wire print_table_start;          // �����ӡ�����ź�??
	wire [3:0] debug_state;          // ����״̬ (����LED��ʾ)
	
	// Print Table ģ�� - ��ӡ������Ϣ��
	// ������: info_table -> print_table -> UART TX
	print_table u_print_table (
		.clk(clk),
		.rst_n(rst_n),
		.start(print_table_start),         // ����: ������ӡ����
		.uart_tx_busy(uart_tx_busy),       // ����: UARTæ״̬
		.uart_tx_en(uart_tx_en_table),     // ���??: UART����ʹ��
		.uart_tx_data(uart_tx_data_table), // ���??: UART��������
		.info_table(info_table),           // ����: ������Ϣ��
		.cnt(total_count),                 // ����: ��������
		.busy(print_busy_table),           // ���??: ģ��æ״̬
		.done(print_done_table),           // ���??: ��ӡ���??
		.current_state(debug_state)        // ���??: ��ǰ״̬
	);

	// --- Print Specified Matrix ��ӡָ�������ź� ---
	wire print_spec_start;               // ������ӡָ������
	wire [2:0] spec_dim_m, spec_dim_n;   // �û������Ŀ�����ά��
	wire print_spec_busy;                // ��ӡָ������æ״̬
	wire print_spec_done;                // ��ӡָ���������??
	wire print_spec_error;               // ��ӡָ���������??
	
	// Matrix Printer for Display ��ʾģʽ�����ӡ�ź�??
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
	wire display_done;                   // ��ʾģʽ���??
	wire [1:0] selected_matrix_id;       // ѡ�еľ���ID

	// --- matrix_selector_display 的矩阵打印接�?? ---
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
		
		// ��print_tableģ�������??
		.print_table_start(print_table_start), // ���??: ������ӡ����
		.print_table_busy(print_busy_table),   // ����: �����ӡ�?
		.print_table_done(print_done_table),   // ����: �����ӡ���
		
		// UART���� - �����û������ά��??
		.uart_input_data(uart_rx_data),        // ����: UART��������
		.uart_input_valid(uart_rx_done),       // ����: UART������Ч
		
		// ��print_specified_dim_matrixģ�������??
		.print_spec_start(print_spec_start),   // ���??: ������ӡָ������
		.spec_dim_m(spec_dim_m),               // ���??: Ŀ���������??
		.spec_dim_n(spec_dim_n),               // ���??: Ŀ���������??
		.print_spec_busy(print_spec_busy),     // ����: ָ����ӡæ
		.print_spec_done(print_spec_done),     // ����: ָ����ӡ���??
		.print_spec_error(print_spec_error),   // ����: ָ����ӡ����
		
		// �?? matrix_storage 通信：读取用户�?�择的矩�??
		.read_en(selector_read_en),
		.rd_col(selector_rd_col),
		.rd_row(selector_rd_row),
		.rd_mat_index(selector_rd_mat_index),
		.rd_data_flow(store_rd_data_flow),
		.rd_ready(store_rd_ready),
		
		// �?? matrix_printer 通信：打印�?�中的矩�??
		.matrix_print_start(selector_print_start),
		.matrix_flat(selector_matrix_flat),
		.matrix_print_busy(selector_print_busy),
		.matrix_print_done(selector_print_done),
		
		// ״̬���??
		.error(display_error),                   // ���??: ����״̬
		.done(display_done),                     // ���??: ���״�?
		.selected_matrix_id(selected_matrix_id)  // ���??: ѡ�еľ���ID
	);

	// Print Specified Dimension Matrix 打印指定维度矩阵模块
	// 数据�??: spec_dim -> info_table 查询 -> matrix_storage 读取 -> 先发计数�?? -> 触发 matrix_printer 打印
	print_specified_dim_matrix u_print_specified_dim_matrix (
		.clk(clk),
		.rst_n(rst_n),
		.start(print_spec_start),             // ����: ������ӡ
		.busy(print_spec_busy),               // ���??: ģ��æ״̬
		.done(print_spec_done),               // ���??: ��ӡ���??
		.error(print_spec_error),             // ���??: ���� (δ�ҵ�ƥ�����??)
		
		// �����Ŀ��ά��??
		.dim_m(spec_dim_m),                   // ����: Ŀ���������??
		.dim_n(spec_dim_n),                   // ����: Ŀ���������??
		
		// ���ӵ�matrix_storage
		.info_table(info_table),              // ����: ������Ϣ�� (���ڲ�ѯ)
		.read_en(spec_read_en),               // ���??: ��ʹ��
		// m=row, n=col: map to storage rd_row, rd_col respectively
		.dimM(spec_rd_row),                   // dimM (row=m) -> rd_row
		.dimN(spec_rd_col),                   // dimN (col=n) -> rd_col
		.mat_index(spec_rd_mat_index),        // ���??: �ȡľ��������??
		.rd_ready(store_rd_ready),            // ����: ��ȡ����
		.rd_data_flow(store_rd_data_flow),    // ����: ��ȡ�ľ�������
		
		// ���ӵ�matrix_printer (ͨ����Щ�źŴ�������)
		.matrix_printer_start(matrix_print_start), // ���??: ����������?
		.matrix_printer_done(matrix_print_done),   // ����: �����ӡ���
		.matrix_flat(matrix_flat),                 // ���??: �������ݴ��ݸ�printer
		.use_crlf(1'b1),                          // ʹ�ûس�����
        
		// UART输出（计数头�??
		.uart_tx_busy(uart_tx_busy),
		.uart_tx_en(uart_tx_en_spec_cnt),
		.uart_tx_data(uart_tx_data_spec_cnt)
	);

	// Matrix Printer for Display 显示模式的矩阵打印器（正文）
	// 数据�??: print_specified_dim_matrix -> matrix_flat -> matrix_printer -> UART TX
	matrix_printer u_print_for_display (
		.clk(clk),
		.rst_n(rst_n),
		.start(matrix_print_start),       // ����: ����print_specified_dim_matrix�������ź�
		.matrix_flat(matrix_flat),        // ����: ����print_specified_dim_matrix�ľ�������
		.dimM(spec_dim_m),                // ����: �������� (ʹ���û������ά��??)
		.dimN(spec_dim_n),                // ����: �������� (ʹ���û������ά��??)
		.use_crlf(1'b1),                  // ʹ�ûس�����
		.tx_start(uart_tx_en_spec_mat),   // ���??: UART����ʹ�� (矩阵正文)
		.tx_data(uart_tx_data_spec_mat),  // ���??: UART�������� (矩阵正文)
		.tx_busy(uart_tx_busy),           // ����: UARTæ״̬
		.done(matrix_print_done)          // ���??: ��ӡ��ɣ�������print_specified_dim_matrix
	);
	// --- Matrix Printer for Selector: matrix_selector_display 用户选择矩阵打印 ---
	matrix_printer u_print_for_selector (
		.clk(clk),
		.rst_n(rst_n),
		.start(selector_print_start),
		.matrix_flat(selector_matrix_flat),
		.dimM(spec_dim_m),                // 使用用户输入的维�??
		.dimN(spec_dim_n),
		.use_crlf(1'b1),
		.tx_start(uart_tx_en_selector),
		.tx_data(uart_tx_data_selector),
		.tx_busy(uart_tx_busy),
		.done(selector_print_done)
	);
	
	// selector_print_busy 根据打印器状态生�??
	assign selector_print_busy = selector_print_start | (~selector_print_done & (selector_print_start | uart_tx_en_selector));
	// Display模式 UART 选择信号（不再使用二选一固定选择�??
	// 由上�?? always 块统�??选择输出�?? uart_tx

	//卷积模块  
	wire conv_done;
	wire conv_busy;
	wire conv_print_enable;
	wire conv_print_done;
	wire conv_uart_tx_en;
	wire [7:0] conv_uart_tx_data;   // 修复：从1位改�?8�?
	wire [1279:0] conv_matrix_flat;
	
	convolution_engine u_convolution_engine (
	.clk(clk),
	.rst(~rst_n),  // 修复：convolution_engine使用高电平复位，�?要取�?
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
	wire [7:0] conv_printer_tx_data;  // 修复：从1位改�?8�?
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
	always @(posedge clk or negedge rst_n) begin
	    if (!rst_n) begin
	        ptr <= 1'b0;
			matrix_selected[0] <= 200'd0;
			matrix_selected[1] <= 200'd0;
			m_selected[0] <= 3'd0;
			m_selected[1] <= 3'd0;
			n_selected[0] <= 3'd0;
	    end else if (display_done) begin
			ptr <= ~ptr;
			matrix_selected[ptr] <= selector_matrix_flat;
			m_selected[ptr] <= spec_dim_m;
			n_selected[ptr] <= spec_dim_n;
	    end
	end

	reg [3:0] calc_mode;
	wire [2:0] op_code = calc_mode[2:0];
	reg calc_start;
	reg error_not_cleaned;

	reg [3:0] state, next_state;
	reg [7:0] scalr_input;
	wire scalar_valid = (scalar >= 8'd0) && (scalar <= 8'd9);

	localparam CALC_IDLE        = 4'd0;
	localparam CALC_WAIT_CONFIRM = 4'd1;
	localparam CALC_BRANCH       = 4'd2;
	localparam CALC_SCALAR_CONFIRM = 4'd3;
	localparam CALC_SCALAR_VALIDATE = 4'd5;
	localparam CALC_COMPUTE    = 4'd4;
	localparam RESULT_WAIT    = 4'd7;
	localparam RESULT_PRINT    = 4'd8;
	localparam ERROR_SCALAR          = 4'd9;
	localparam ERROR_MATRIX      = 4'd10;
	localparam DONE      = 4'd6;


	localparam OP_TRANSPOSE = 3'd0;
	localparam OP_SCALAR = 3'd1;
	localparam OP_ADD       = 3'd2;
	localparam OP_MULTIPLY  = 3'd3;

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
					if(error_not_cleaned) begin
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
				if(op_code == OP_SCALAR) begin
					next_state = CALC_SCALAR_CONFIRM;
				end else begin
					next_state = CALC_COMPUTE;
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
					next_state = DONE;
				end
			end

			DONE:begin
				if(result_valid) begin
					next_state = RESULT_PRINT;
				end else begin
					next_state = ERROR_MATRIX;
				end
			end

			RESULT_PRINT: begin
				if(result_printer_done) begin
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
				next_state = CALC_IDLE;
			end

	        default: begin
	            next_state = CALC_IDLE;
	        end
	    endcase
	end
	always@(*) begin
	    calc_start = 1'b0;
	    calc_mode = 4'd0;
	    scalar = 8'd0;
	    case (next_state)
			CALC_IDLE: begin
			end
			CALC_WAIT_CONFIRM: begin
				if(btn_confirm_db) begin
					calc_mode = command[7:4];
				end
			end
	        CALC_BRANCH: begin
				calc_mode = command[7:4];
			end
			CALC_SCALAR_VALIDATE: begin
				if(scalar_valid) begin
					scalar = scalar_input;
					error_not_cleaned = 1'b0;
				end
			end
			CALC_COMPUTE: begin
				calc_start = 1'b1;
			end
			ERROR_SCALAR: begin
				error_not_cleaned = 1'b1;
			end
			ERROR_MATRIX: begin
				error_not_cleaned = 1'b1;
			end
			DONE: begin
				error_not_cleaned = 1'b0;
			end

	        default: begin
	            // do nothing
	        end
	    endcase
	end

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

	wire [399:0] result_flat;
	wire [2:0] result_m;
	wire [2:0] result_n;
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
	    .scalar(scalar_input), // Example scalar value
	    .result_flat(result_flat),
	    .result_m(result_m),
	    .result_n(result_n),
	    .done(result_done),
	    .valid(result_valid),
	    .busy(result_busy)
	);

endmodule