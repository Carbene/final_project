// ========================================
// Convolution-only Top Module (conv_top)
// ========================================
// Purpose: Isolate and debug convolution pipeline
// UART RX -> convolution_engine -> (matrix) conv_matrix_printer -> UART TX
// Notes:
// - convolution_engine uses active-high reset (.rst), others use active-low (.rst_n)
// - Adds gating so conv logic only consumes RX/TX when enable=1
// - Provides simple debug LEDs for busy/done/print
// ========================================

module conv_top(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,        // drive high to enable convolution feature
    input  wire        uart_rxd,
    output wire        uart_txd,
    output reg  [7:0]  dbg_led        // {print_done, print_enable, busy, done, uart_tx_busy, rx_valid, tx_select, reserved}
);

    // UART RX
    wire        uart_rx_done;
    wire [7:0]  uart_rx_data;
    uart_rx u_uart_rx(
        .clk     (clk     ),
        .rst_n   (rst_n   ),
        .uart_rxd(uart_rxd),
        .uart_rx_done(uart_rx_done),
        .uart_rx_data(uart_rx_data)
    );

    // UART TX
    reg         uart_tx_en;
    reg  [7:0]  uart_tx_data;
    wire        uart_tx_busy;
    uart_tx u_uart_tx(
        .clk     (clk     ),
        .rst_n   (rst_n   ),
        .uart_tx_en(uart_tx_en),
        .uart_tx_data(uart_tx_data),
        .uart_txd(uart_txd),
        .uart_tx_busy(uart_tx_busy)
    );

    // Convolution engine (removed UART interface, added cycles_counter_out)
    wire        conv_done;
    wire        conv_busy;
    wire        conv_print_enable;
    wire        conv_print_done;
    wire [1279:0] conv_matrix_flat;
    wire [15:0]  cycles_counter_out;  // new output

    convolution_engine u_convolution_engine(
        .clk     (clk     ),
        .rst     (~rst_n  ),  // active-high reset
        .enable  (enable  ),
        .uart_rx_valid(uart_rx_done),
        .uart_rx_data(uart_rx_data),
        .done    (conv_done),
        .busy    (conv_busy),
        .print_enable(conv_print_enable),
        .matrix_data(conv_matrix_flat),
        .print_done(conv_print_done),
        .cycles_counter_out(cycles_counter_out)  // new
    );

    // Matrix printer
    wire        printer_tx_start;
    wire [7:0]  printer_tx_data;

    conv_matrix_printer u_conv_matrix_printer(
        .clk     (clk     ),
        .rst_n   (rst_n   ),
        .start   (conv_print_enable),
        .matrix_flat(conv_matrix_flat),
        .tx_busy (uart_tx_busy),
        .tx_start(printer_tx_start),
        .tx_data (printer_tx_data),
        .done    (conv_print_done)
    );

    // Cycles printer (starts after matrix print done)
    wire        cycles_tx_start;
    wire [7:0]  cycles_tx_data;
    wire        cycles_done;

    print_cycles u_print_cycles(
        .clk     (clk     ),
        .rst_n   (rst_n   ),
        .start   (conv_print_done),  // start after matrix print done
        .cycles  (cycles_counter_out),
        .tx_busy (uart_tx_busy),
        .tx_start(cycles_tx_start),
        .tx_data (cycles_tx_data),
        .done    (cycles_done)
    );

    // UART TX arbitration
    wire tx_select_printer = conv_print_enable & enable;
    wire tx_select_cycles  = conv_print_done & enable;  // after matrix done

    always @(*) begin
        if (tx_select_printer) begin
            uart_tx_en   = printer_tx_start;
            uart_tx_data = printer_tx_data;
        end else if (tx_select_cycles) begin
            uart_tx_en   = cycles_tx_start;
            uart_tx_data = cycles_tx_data;
        end else begin
            uart_tx_en   = 1'b0;
            uart_tx_data = 8'h00;
        end
    end

    // Debug LEDs
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dbg_led <= 8'h00;
        end else begin
            dbg_led[7] <= conv_print_done;
            dbg_led[6] <= conv_print_enable;
            dbg_led[5] <= conv_busy;
            dbg_led[4] <= cycles_done;  // new: cycles print done
            dbg_led[3] <= uart_tx_busy;
            dbg_led[2] <= uart_rx_done & enable;
            dbg_led[1] <= tx_select_printer;
            dbg_led[0] <= tx_select_cycles;  // new: cycles print active
        end
    end

endmodule