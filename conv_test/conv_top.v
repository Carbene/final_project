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
        .clk(clk),
        .rst_n(rst_n),
        .uart_rxd(uart_rxd),
        .uart_rx_done(uart_rx_done),
        .uart_rx_data(uart_rx_data)
    );

    // UART TX
    reg         uart_tx_en;
    reg  [7:0]  uart_tx_data;
    wire        uart_tx_busy;
    uart_tx u_uart_tx(
        .clk(clk),
        .rst_n(rst_n),
        .uart_tx_en(uart_tx_en),
        .uart_tx_data(uart_tx_data),
        .uart_txd(uart_txd),
        .uart_tx_busy(uart_tx_busy)
    );

    // Convolution engine
    wire        conv_done;
    wire        conv_busy;
    wire        conv_print_enable;
    wire        conv_print_done;
    wire        conv_uart_tx_valid;
    wire [7:0]  conv_uart_tx_data;
    wire [1279:0] conv_matrix_flat; // 80 * 16 bytes

    convolution_engine u_convolution_engine(
        .clk(clk),
        .rst(~rst_n),                 // active-high reset
        .enable(enable),
        .uart_rx_valid(uart_rx_done & enable), // gate RX consumption
        .uart_rx_data(uart_rx_data),
        .done(conv_done),
        .busy(conv_busy),
        .print_enable(conv_print_enable),
        .matrix_data(conv_matrix_flat),
        .print_done(conv_print_done),
        .uart_tx_valid(conv_uart_tx_valid),
        .uart_tx_data(conv_uart_tx_data),
        .uart_tx_ready(~uart_tx_busy & enable)    // gate TX handshake
    );

    // Convolution matrix printer (prints matrix rows when print_enable=1)
    wire        conv_printer_tx_start;
    wire [7:0]  conv_printer_tx_data;
    conv_matrix_printer u_conv_matrix_printer(
        .clk(clk),
        .rst_n(rst_n),
        .start(conv_print_enable & enable),
        .matrix_flat(conv_matrix_flat),
        .tx_busy(uart_tx_busy),
        .tx_start(conv_printer_tx_start),
        .tx_data(conv_printer_tx_data),
        .done(conv_print_done)
    );

    // UART TX arbitration inside convolution-only top
    // Prefer matrix printer when printing is enabled; otherwise send control/status bytes
    wire tx_select_printer = conv_print_enable & enable; // 1=printer, 0=engine
    always @(*) begin
        if (tx_select_printer) begin
            uart_tx_en   = conv_printer_tx_start;
            uart_tx_data = conv_printer_tx_data;
        end else begin
            uart_tx_en   = conv_uart_tx_valid;
            uart_tx_data = conv_uart_tx_data;
        end
    end

    // Simple debug LEDs
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dbg_led <= 8'h00;
        end else begin
            dbg_led[0] <= 1'b0;                            // reserved
            dbg_led[1] <= tx_select_printer;               // current TX source select
            dbg_led[2] <= uart_rx_done & enable;           // rx_valid gated
            dbg_led[3] <= uart_tx_busy;                    // uart tx busy
            dbg_led[4] <= conv_done;                       // engine done pulse
            dbg_led[5] <= conv_busy;                       // engine busy
            dbg_led[6] <= conv_print_enable;               // printer enable
            dbg_led[7] <= conv_print_done;                 // printer done
        end
    end

endmodule
