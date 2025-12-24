`timescale 1ns / 1ps
// Packed-Matrix ASCII formatter (16-bit elements, <= 999):
// Reads a 400-bit row-major packed matrix (up to 25 elements, 16-bit each)
// and handshakes bytes to uart_tx, formatting elements as decimal with tab separators
// and CR/LF row ends. Handshake matches uart_tx.v (yuanzige) semantics.

module matrix_printer16 #(
    parameter ADDR_WIDTH   = 8,     // enough for idx up to total_ops (<=25)
    parameter ELEM_WIDTH   = 16,    // fixed 16-bit elements
    parameter MAX_ELEMS    = 25,    // max elements (5x5)
    parameter PACKED_WIDTH = MAX_ELEMS * ELEM_WIDTH // 400 bits
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     start,
    input  wire [2:0]               dimM,        // rows (<= 5)
    input  wire [2:0]               dimN,        // cols (<= 5)
    input  wire [PACKED_WIDTH-1:0]  matrix_flat, // row-major: element k at [k*16 +: 16]
    input  wire                     use_crlf,    // 0: \n, 1: \r\n at row ends
    input  wire                     tx_busy,
    output reg                      tx_start,
    output reg  [7:0]               tx_data,
    output reg                      done
);

    localparam IDLE   = 3'd0,
               LOAD   = 3'd1,
               FORMAT = 3'd2,
               SEND   = 3'd3,
               ADV    = 3'd4,
               DONE_S = 3'd5;

    reg  [2:0]            state, next_state;
    reg  [ADDR_WIDTH-1:0] idx;
    reg  [2:0]            col;
    reg  [ELEM_WIDTH-1:0] val_reg;

    reg  [2:0]            send_phase;
    reg                   send_done;
    reg                   wait_tx_done;

    wire [ADDR_WIDTH-1:0] total_ops;
    wire                  col_last;

    wire [1:0]            digit_count;   // 1..3
    wire [3:0]            hundreds_calc; // 0..9
    wire [3:0]            tens_calc;     // 0..9
    wire [3:0]            ones_calc;     // 0..9

    wire [2:0]            separator_len; // 1 or 2
    wire [2:0]            send_count;    // digit_count + separator_len (max 5)
    wire [2:0]            send_phase_max;

    reg  [7:0]            send_byte;

    // total elements = dimM * dimN
    assign total_ops = dimM * dimN;

    // true when current element is the last in the row
    assign col_last = (col + 1'b1 == dimN);

    // decimal digit count for 0..999 (no leading zeros)
    assign digit_count = (val_reg >= 16'd100) ? 2'd3 :
                         (val_reg >= 16'd10)  ? 2'd2 : 2'd1;

    // compute decimal digits (0..999)
    // NOTE: division by constants is synthesizable in FPGA tools.
    wire [15:0] val_mod_100;
    assign hundreds_calc = (val_reg >= 16'd100) ? (val_reg / 16'd100) : 4'd0;
    assign val_mod_100   = val_reg - (hundreds_calc * 16'd100);
    assign tens_calc     = (val_reg >= 16'd10)  ? (val_mod_100 / 16'd10) : 4'd0;
    assign ones_calc     = val_mod_100 - (tens_calc * 16'd10);

    // Separator/newline sizing
    assign separator_len  = col_last ? (use_crlf ? 3'd2 : 3'd1) : 3'd1;
    assign send_count     = digit_count + separator_len;
    assign send_phase_max = send_count - 1'b1;

    // choose next byte based on phase (digits first, then separator/newline)
    always @(*) begin
        if (send_phase < digit_count) begin
            case (digit_count)
                2'd3: begin
                    if (send_phase == 3'd0)       send_byte = 8'd48 + hundreds_calc;
                    else if (send_phase == 3'd1)  send_byte = 8'd48 + tens_calc;
                    else                          send_byte = 8'd48 + ones_calc;
                end
                2'd2: begin
                    if (send_phase == 3'd0)       send_byte = 8'd48 + tens_calc;
                    else                          send_byte = 8'd48 + ones_calc;
                end
                default: begin
                    send_byte = 8'd48 + ones_calc;
                end
            endcase
        end else begin
            if (col_last) begin
                if (use_crlf) begin
                    send_byte = (send_phase == digit_count) ? 8'h0D : 8'h0A; // \r then \n
                end else begin
                    send_byte = 8'h0A; // \n
                end
            end else begin
                send_byte = 8'h09; // Tab (ASCII 9)
            end
        end
    end

    // next state logic
    always @(*) begin
        next_state = state;
        case (state)
            IDLE:    next_state = start ? LOAD : IDLE;
            LOAD:    next_state = (total_ops == 0) ? DONE_S : FORMAT;
            FORMAT:  next_state = SEND;
            SEND:    next_state = send_done ? ADV : SEND;
            ADV:     next_state = ((idx + 1'b1 >= total_ops) ? DONE_S : LOAD);
            DONE_S:  next_state = start ? DONE_S : IDLE;
            default: next_state = IDLE;
        endcase
    end

    // sequential logic: state register, counters, and UART handshakes
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            idx          <= {ADDR_WIDTH{1'b0}};
            col          <= 3'd0;
            val_reg      <= {ELEM_WIDTH{1'b0}};
            send_phase   <= 3'd0;
            send_done    <= 1'b0;
            tx_start     <= 1'b0;
            wait_tx_done <= 1'b0;
            tx_data      <= 8'h00;
            done         <= 1'b0;
        end else begin
            state <= next_state;
            // default outputs
            tx_start <= tx_start;
            done     <= 1'b0;

            case (state)
                IDLE: begin
                    idx          <= {ADDR_WIDTH{1'b0}};
                    col          <= 3'd0;
                    send_phase   <= 3'd0;
                    send_done    <= 1'b0;
                    tx_start     <= 1'b0;
                    wait_tx_done <= 1'b0;
                end

                LOAD: begin
                    send_phase   <= 3'd0;
                    send_done    <= 1'b0;
                    tx_start     <= 1'b0;
                    wait_tx_done <= 1'b0;
                end

                FORMAT: begin
                    // slice current element from packed input (row-major)
                    val_reg <= matrix_flat[(idx*ELEM_WIDTH) +: ELEM_WIDTH];
                end

                SEND: begin
                    // uart_tx.v latches data whenever uart_tx_en is high.
                    // Therefore: assert tx_start only when !tx_busy, then drop once tx_busy rises,
                    // and wait for tx_busy to fall before sending next byte.
                    if (!wait_tx_done && !tx_busy && !send_done) begin
                        tx_data      <= send_byte;
                        tx_start     <= 1'b1;
                        wait_tx_done <= 1'b1;
                    end else if (wait_tx_done && tx_busy) begin
                        tx_start <= 1'b0;
                    end else if (wait_tx_done && !tx_busy && tx_start == 1'b0) begin
                        wait_tx_done <= 1'b0;
                        if (send_phase == send_phase_max) begin
                            send_done <= 1'b1;
                        end else begin
                            send_phase <= send_phase + 1'b1;
                        end
                    end
                end

                ADV: begin
                    if (idx + 1'b1 < total_ops) begin
                        idx <= idx + 1'b1;
                        if (col_last) begin
                            col <= 3'd0;
                        end else begin
                            col <= col + 1'b1;
                        end
                    end
                end

                DONE_S: begin
                    done <= 1'b1;
                end

                default: begin
                    // no-op
                end
            endcase
        end
    end

endmodule
