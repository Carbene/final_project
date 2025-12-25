module table_top_test(
    input wire clk,
    input wire rst_n,
    input wire [2:0] command,
    input wire btn_confirm,
    input uart_rxd,
    output uart_txd
);

    Central_Controller u_central_controller (
        .clk(clk),
        .rst_n(rst_n),
        .command(command),
        .btn_confirm(btn_confirm),
        .btn_exit(1'b0), // For testing, exit button is not pressed

        .input_mode_exitable(1'b1),
        .data_input_mode_en(),
        .generate_mode_exitable(1'b1),
        .generate_mode_en(),
        .display_mode_exitable(1'b1),
        .display_mode_en(),
        .calculation_mode_exitable(1'b1),
        .calculation_mode_en()
    );
    uart_rx u_uart_rx (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rxd(uart_rxd),
        .uart_rx_done(),
        .uart_rx_data()
    );
    uart_tx u_uart_tx (
        .clk(clk),
        .rst_n(rst_n),
        .uart_tx_en(1'b0), // For testing, no data to send
        .uart_tx_data(8'd0),
        .uart_txd(uart_txd),
        .uart_tx_busy()
    );
    debounce u_debounce_confirm (
        .clk(clk),
        .rst_n(rst_n),
        .btn_in(btn_confirm),
        .btn_out(),
        .pulse()
    );
    matrix_storage u_matrix_storage (
        .clk(clk),
        .rst_n(rst_n),
        .write_en(1'b0),
        .mat_col(3'd0),
        .mat_row(3'd0),
        .data_flow(200'd0),
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
    print_table u_print_table (
        .clk(clk),
        .rst_n(rst_n),
        .start(1'b0),
        .uart_tx_busy(1'b0),
        .uart_tx_en(),
        .uart_tx_data(),
        .info_table(50'd0),
        .cnt(8'd0),
        .busy(),
        .done(),
        .dout(),
        .dout_valid()
    );

endmodule