// 顶层模块：sys_top

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


	// --- 按键消抖 ---
	wire btn_confirm_db;
	btn_debouncer u_btn_debouncer(
		.clk(clk),
		.rst_n(rst_n),
		.btn_in(btn_confirm),
		.btn_out(btn_confirm_db),
        .pulse()
	);
    wire btn_exit_db;
    btn_debouncer u_btn_exit_debouncer(
        .clk(clk),
        .rst_n(rst_n),
        .btn_in(btn_exit),
        .btn_out(btn_exit_db),
        .pulse()
    );
    // --- UART RX ---
	wire uart_rx_done;
	wire [7:0] uart_rx_data;
	uart_rx u_rx(
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

	// --- print信号总线 ---
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
	wire generate_mode_en, display_mode_en, calculation_mode_en;
	// 其它mode_exitable信号暂时拉高
	wire input_mode_exitable = 1'b1;
	wire generate_mode_exitable = 1'b1;
	wire display_mode_exitable = 1'b1;
	wire calculation_mode_exitable = 1'b1;//?
    // mode指示灯
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
		.command(command[2:0]), // 只用低3位，后续可扩展
		.btn_confirm(btn_confirm_db),
		.btn_exit(btn_exit_db),
		.input_mode_exitable(input_mode_exitable),
		.data_input_mode_en(data_input_mode_en),
		.generate_mode_exitable(generate_mode_exitable),
		.generate_mode_en(generate_mode_en),
		.display_mode_exitable(display_mode_exitable),
		.display_mode_en(display_mode_en),
		.calculation_mode_exitable(calculation_mode_exitable),
		.calculation_mode_en(calculation_mode_en)
	);

	// --- Ld2/数码管输出 ---
	reg led0_on;
	reg [24:0] led0_cnt; // 0.5秒计数，假设50MHz时钟，0.5s=25_000_000
	reg led1_on; // gen_done指示灯
	reg [24:0] led1_cnt;
	reg led2_on; // gen_error指示灯
	reg [24:0] led2_cnt;
	reg led3_on; // gen_valid指示灯
	reg [24:0] led3_cnt;
	wire [7:0] ld2_wire;
	assign ld2_wire = {7'd0, led0_on};


	// 数码管显示数据暂未使用，全部拉低
	assign seg_data0 = 8'd0;
	assign seg_data1 = 8'd0;
	assign seg_sel0 = 8'd0;
	assign seg_sel1 = 8'd0;

	// --- led0控制逻辑 ---
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

	// --- led1控制逻辑 (gen_done指示) ---
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

	// --- led2控制逻辑 (gen_error指示) ---
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

	// --- led3控制逻辑 (gen_valid指示) ---
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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ld2 <= 8'd0;
        end else begin
            ld2[0] <= ld2_wire[0]; // 写存储指示
            ld2[1] <= led1_on;     // gen_done延长显示
            ld2[2] <= led2_on;     // gen_error延长显示
            ld2[3] <= led3_on;     // gen_valid延长显示
            ld2[7:4] <= 4'd0;      // 保持其他位为0
        end
    end

	

	// --- UART Parser ---
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
	


	// --- Matrix Store (200位) ---
    //信号变换
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
		end else if (parse_done) begin		//输入模块的存储
			store_write_en <= 1'b1;
			store_mat_col <= parsed_m;
			store_mat_row <= parsed_n;
			store_data_flow <= parsed_matrix_flat;
		end else if (gen_valid) begin		//生成模块的存储
			store_write_en <= 1'b1;
			store_mat_col <= gen_m;
			store_mat_row <= gen_n;
			store_data_flow <= gen_flow;
		end else begin
			store_write_en <= 1'b0;
		end
	end

	// 只实现写入，读接口暂未用
	matrix_storage #(
		.DATAWIDTH(8),
		.MAXNUM(2),
		.PICTUREMATRIXSIZE(25)
	) u_store (
		.clk(clk),
		.rst_n(rst_n),
		.write_en(store_write_en),
		.mat_col(store_mat_col),
		.mat_row(store_mat_row),
		.data_flow(store_data_flow),
		.read_en(1'b0),
		.rd_col(3'd0),
		.rd_row(3'd0),
		.rd_mat_index(2'd0),
		.rd_data_flow(),
		.rd_ready(),
		.err_rd(),
		.total_count(),
		.info_table()
	);
	// generator_operate模块的输入
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

	// --- Print模块信号 ---
	// Parse模式打印信号
	wire uart_tx_en_parse;
	wire [7:0] uart_tx_data_parse;
	wire print_done_parse;

	// Generate模式打印信号
	wire uart_tx_en_gen;
	wire [7:0] uart_tx_data_gen;
	wire print_done_gen;

	// 根据模式选择UART TX信号源
	always @(*) begin
		if (data_input_mode_en) begin
			uart_tx_en = uart_tx_en_parse;
			uart_tx_data = uart_tx_data_parse;
		end else if (generate_mode_en) begin
			uart_tx_en = uart_tx_en_gen;
			uart_tx_data = uart_tx_data_gen;
		end else begin
			uart_tx_en = 1'b0;
			uart_tx_data = 8'd0;
		end
	end

	//Print for parse
	matrix_printer u_print_for_parse (
		.clk(clk),
		.rst_n(rst_n),
		.start(parse_done),
		.matrix_flat(parsed_matrix_flat),
		.dim_m(parsed_m),
		.dim_n(parsed_n),
		.use_crlf(1'b1),
		.tx_start(uart_tx_en_parse),
		.tx_data(uart_tx_data_parse),
		.tx_busy(uart_tx_busy),
		.done(print_done_parse)
	);


    // --- Print  For Gnerate---
	matrix_printer u_print_for_generate (
		.clk(clk),
		.rst_n(rst_n),
		.start(gen_valid),
		.matrix_flat(gen_flow),
		.dim_m(gen_m),
		.dim_n(gen_n),
		.use_crlf(1'b1),
		.tx_start(uart_tx_en_gen),
		.tx_data(uart_tx_data_gen),
		.tx_busy(uart_tx_busy),
		.done(print_done_gen)
	);
    


    // --- Print table For Display---
	wire [49:0] info_table;





    // --- Print for calculate ---

	

endmodule
