`timescale 1ns / 1ps
// Convolution Result Printer (fixed 8x10, 16-bit elements)
// - Prints each element as 4 right-aligned characters: [space][hundreds][tens][ones]
// - Rows end with CRLF ("\r\n")
// - Input packed matrix_flat: 80 elements (row-major), element k at [k*16 +: 16]
// - Handshake matches uart_tx.v semantics: tx_start -> uart_tx_en, tx_busy from uart_tx

module conv_matrix_printer (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,               // start printing when high (one-shot or level)
    input  wire [1279:0] matrix_flat,      // 80 * 16
    input  wire        tx_busy,
    output reg         tx_start,           // drive uart_tx_en
    output reg  [7:0]  tx_data,            // drive uart_tx_data
    output reg         done                // pulses high when all rows sent
);

    localparam ROWS = 8;
    localparam COLS = 10;
    localparam TOTAL = ROWS * COLS; // 80

    localparam S_IDLE   = 3'd0;
    localparam S_LOAD   = 3'd1;
    localparam S_FORMAT = 3'd2;
    localparam S_SEND   = 3'd3;
    localparam S_ADV    = 3'd4;
    localparam S_DONE   = 3'd5;

    reg  [2:0]  state, next_state;
    reg  [6:0]  idx;        // 0..79
    reg  [3:0]  col;        // 0..9
    reg  [15:0] val_reg;    // current element

    // digit computations
    wire [3:0] hundreds = (val_reg >= 16'd100) ? (val_reg / 16'd100) : 4'd0;
    wire [15:0] mod100   = val_reg - (hundreds * 16'd100);
    wire [3:0] tens     = (val_reg >= 16'd10) ? (mod100 / 16'd10) : 4'd0;
    wire [3:0] ones     = mod100 - (tens * 16'd10);

    // right-aligned 4 columns: [space][hundreds or space][tens or space][ones]
    reg  [2:0] send_phase;       // 0..3 for element bytes, then CRLF when col_last
    reg        send_done;        // element fully sent
    reg        wait_tx_done;     // handshake edge tracking
    reg        do_crlf;          // after last column of row
    reg  [7:0] send_byte;

    wire       col_last = (col == COLS-1);

    // pick byte to send for current phase
    always @(*) begin
        if (!do_crlf) begin
            // element bytes
            case (send_phase)
                3'd0: send_byte = 8'h20; // leading space for thousands place
                3'd1: send_byte = (val_reg >= 16'd100) ? (8'd48 + hundreds) : 8'h20; // hundreds or space
                3'd2: send_byte = (val_reg >= 16'd10)  ? (8'd48 + tens)     : 8'h20; // tens or space
                default: send_byte = 8'd48 + ones; // ones
            endcase
        end else begin
            // CRLF after row end
            // phase 0: '\r', phase 1: '\n'
            send_byte = (send_phase == 3'd0) ? 8'h0D : 8'h0A;
        end
    end

    // next state
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE:   next_state = start ? S_LOAD : S_IDLE;
            S_LOAD:   next_state = (idx >= TOTAL) ? S_DONE : S_FORMAT;
            S_FORMAT: next_state = S_SEND;
            S_SEND:   next_state = send_done ? S_ADV : S_SEND;
            S_ADV:    next_state = (idx + 1'b1 >= TOTAL) ? S_DONE : S_LOAD;
            S_DONE:   next_state = start ? S_DONE : S_IDLE; // wait for start to deassert
            default:  next_state = S_IDLE;
        endcase
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
        end else begin
            state <= next_state;
        end
    end

    // sequential
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            idx          <= 7'd0;
            col          <= 4'd0;
            val_reg      <= 16'd0;
            send_phase   <= 3'd0;
            send_done    <= 1'b0;
            tx_start     <= 1'b0;
            wait_tx_done <= 1'b0;
            tx_data      <= 8'h00;
            done         <= 1'b0;
            do_crlf      <= 1'b0;
        end else begin
            done  <= 1'b0; // default

            case (state)
                S_IDLE: begin
                    idx          <= 7'd0;
                    col          <= 4'd0;
                    send_phase   <= 3'd0;
                    send_done    <= 1'b0;
                    tx_start     <= 1'b0;
                    wait_tx_done <= 1'b0;
                    do_crlf      <= 1'b0;
                end

                S_LOAD: begin
                    // prepare counters
                    send_phase   <= 3'd0;
                    send_done    <= 1'b0;
                    tx_start     <= 1'b0;
                    wait_tx_done <= 1'b0;
                    do_crlf      <= 1'b0;
                end

                S_FORMAT: begin
                    // slice current element
                    val_reg <= matrix_flat[(idx*16) +: 16];
                end

                S_SEND: begin
                    // element send phases 0..3; if last column, after element send CRLF with phases 0..1
                    if (!wait_tx_done && !tx_busy && !send_done) begin
                        tx_data      <= send_byte;
                        tx_start     <= 1'b1;
                        wait_tx_done <= 1'b1;
                    end else if (wait_tx_done && tx_busy) begin
                        tx_start <= 1'b0;
                    end else if (wait_tx_done && !tx_busy && tx_start == 1'b0) begin
                        wait_tx_done <= 1'b0;
                        // advance phase
                        if (!do_crlf) begin
                            if (send_phase == 3'd3) begin
                                // element finished
                                if (col_last) begin
                                    // start CRLF send
                                    do_crlf    <= 1'b1;
                                    send_phase <= 3'd0; // CR first
                                end else begin
                                    send_done  <= 1'b1;
                                end
                            end else begin
                                send_phase <= send_phase + 1'b1;
                            end
                        end else begin
                            // CRLF phases: 0 (CR), 1 (LF)
                            if (send_phase == 3'd1) begin
                                send_done <= 1'b1;
                                do_crlf   <= 1'b0; // reset for next element
                            end else begin
                                send_phase <= send_phase + 1'b1;
                            end
                        end
                    end
                end

                S_ADV: begin
                    if (idx + 1'b1 < TOTAL) begin
                        idx <= idx + 1'b1;
                        if (col_last) begin
                            col <= 4'd0;
                        end else begin
                            col <= col + 1'b1;
                        end
                    end
                end

                S_DONE: begin
                    done <= 1'b1;
                end

                default: begin
                    // no-op
                end
            endcase
        end
    end

endmodule
