
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
    // --- print信号选择 ---
	assign print_busy = data_input_mode_en ? print_busy_ind : 1'b0;
	assign print_done = data_input_mode_en ? print_done_ind : 1'b0;
	assign print_dout = data_input_mode_en ? print_dout_ind : 8'd0;//改成if
    assign print_dout_valid = data_input_mode_en ? print_dout_valid_ind : 1'b0;


	// 错误点：下面这个always块只会在print_busy刚变高时发送第一个字节，
	// 后续print_busy为高期间，print_sent一直为1，导致不会再发第二个字节，
	// 所以UART只会收到一个字符。
	// 正确做法：应让每个字节都能单独触发发送。
	// 推荐改法：让print_matrix模块输出一个dout_valid信号，每次dout_valid为1时，uart_tx_en拉高一个周期。
	// 如果没有dout_valid，可以用print_busy的下降沿或done信号配合实现。
	// 修正后：每次print_dout_valid为高且uart_tx不忙时，发送一个字节
	always @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			uart_tx_en <= 1'b0;
			uart_tx_data <= 8'd0;
		end else if (print_dout_valid && !uart_tx_busy) begin
			uart_tx_en <= 1'b1;
			uart_tx_data <= print_dout;
		end else begin
			uart_tx_en <= 1'b0;
		end
	end

	/*
	// 修正建议：
	// 1. 在print_matrix模块增加dout_valid信号，每输出一个新字节时dout_valid拉高1拍。
	// 2. 用如下方式控制uart_tx_en：
	always @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			uart_tx_en <= 1'b0;
			uart_tx_data <= 8'd0;
		end else if (print_dout_valid && !uart_tx_busy) begin
			uart_tx_en <= 1'b1;
			uart_tx_data <= print_dout;
		end else begin
			uart_tx_en <= 1'b0;
		end
	end
	// 这样每个字节都能被正确发送。
	*/
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
	wire [7:0] ld2_wire;
	assign ld2_wire = {7'd0, led0_on};
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
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ld2 <= 8'd0;
        end else begin
            ld2 <= ld2_wire;
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
		end else if (parse_done) begin
			store_write_en <= 1'b1;
			store_mat_col <= parsed_m;
			store_mat_row <= parsed_n;
			store_data_flow <= parsed_matrix_flat;
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

	// --- Print Matrix For Input---
	wire print_start_ind = parse_done;
	wire print_busy_ind, print_done_ind;
	wire [7:0] print_dout_ind;
	wire print_dout_valid_ind;
	// 只在输入模式下将uart_tx_busy连接到print_matrix，否则为0，防止其他模式下信号冲突
	wire print_uart_tx_busy = data_input_mode_en ? uart_tx_busy : 1'b0;
	print_matrix u_auto_input(
		.clk(clk),
		.rst_n(rst_n),
		.data_input(parsed_matrix_flat),
		.width(parsed_m),
		.height(parsed_n),
		.start(print_start_ind),
		.uart_tx_busy(print_uart_tx_busy),
		.busy(print_busy_ind),
		.done(print_done_ind),
		.dout(print_dout_ind),
		.dout_valid(print_dout_valid_ind)
	);
    // --- Print  For Gnerate---
    


    // --- Print  For Display---




    // --- Print for calculate ---

	

endmodule
