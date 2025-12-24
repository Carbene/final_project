`timescale 1ns / 1ps
// Packed-Matrix ASCII formatter: reads a 200-bit row-major matrix (up to 25 elements, 8-bit each)
// and handshakes bytes to uart_tx, formatting elements as decimal with tab separators and CR/LF row ends.
// Interface mirrors matrix_uart_formatter's UART side (tx_busy/tx_start/tx_data) and control (start/done).

module matrix_printer #(
    parameter ADDR_WIDTH  = 8,    // enough for idx up to total_ops (<=25)
    parameter ELEM_WIDTH  = 8,    // element bit width (fixed 8 per requirements)
    parameter MAX_ELEMS   = 25,   // max elements (5x5)
    parameter PACKED_WIDTH = MAX_ELEMS * ELEM_WIDTH // 200 bits
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     start,
    input  wire [2:0]               dimM,        // rows (<= 5) - 修正为3位
    input  wire [2:0]               dimN,        // cols (<= 5) - 修正为3位
    input  wire [PACKED_WIDTH-1:0]  matrix_flat, // row-major: element k at [k*8 +: 8]
    input  wire                     use_crlf,    // 0: \n, 1: \r\n at row ends
    input  wire                     tx_busy,
    output reg                      tx_start,
    output reg  [7:0]               tx_data,
    output reg                      done
);

    localparam IDLE = 3'd0, LOAD = 3'd1, FORMAT = 3'd2, SEND = 3'd3, ADVANCE = 3'd4, DONE_S = 3'd5;

    reg  [2:0]              state, next_state;
    reg  [ADDR_WIDTH-1:0]   idx;
    reg  [2:0]              col;
    reg  [ELEM_WIDTH-1:0]   val_reg;
    reg  [2:0]              send_phase;
    reg                     send_done;
    reg                     wait_tx_done; // 等待uart_tx完成当前字节

    wire [ADDR_WIDTH-1:0]   total_ops;
    wire                    col_last;
    wire [3:0]              tens_calc;
    wire [3:0]              ones_calc;
    wire [1:0]              digit_count;
    wire [2:0]              separator_len;
    wire [2:0]              send_count;
    wire [2:0]              send_phase_max;
    reg  [7:0]              send_byte;

    // total elements = dimM * dimN
    assign total_ops = dimM * dimN;

    // true when current element is the last in the row
    assign col_last = (col + 1'b1 == dimN[2:0]);

    // Elements guaranteed < 100 (no hundreds). Use generic div-by-10 for tens.
    assign digit_count = (val_reg >= 8'd10) ? 2'd2 : 2'd1;
    assign tens_calc   = (val_reg >= 8'd10) ? (val_reg / 8'd10) : 4'd0; // 0..9
    assign ones_calc   = val_reg - (tens_calc * 4'd10);

    // Separator/newline sizing
    assign separator_len  = col_last ? (use_crlf ? 3'd2 : 3'd1) : 3'd1;
    assign send_count     = digit_count + separator_len;
    assign send_phase_max = send_count - 1'b1;

    // choose next byte based on phase (digits first, then separator/newline)
    always @(*) begin
        if (send_phase < digit_count) begin
            if (digit_count == 2'd2) begin
                send_byte = (send_phase == 0) ? (8'd48 + tens_calc) : (8'd48 + ones_calc);
            end else begin
                send_byte = 8'd48 + ones_calc;
            end
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
            IDLE:     next_state = start ? LOAD : IDLE;
            LOAD:     next_state = (total_ops == 0) ? DONE_S : FORMAT;
            FORMAT:   next_state = SEND;
            SEND:     next_state = send_done ? ADVANCE : SEND;
            ADVANCE:  next_state = ((idx + 1'b1 >= total_ops) ? DONE_S : LOAD);
            DONE_S:   next_state = start ? DONE_S : IDLE;
            default:  next_state = IDLE;
        endcase
    end

    // sequential logic: state register, counters, and handshakes
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            idx           <= {ADDR_WIDTH{1'b0}};
            col           <= 3'd0;
            val_reg       <= {ELEM_WIDTH{1'b0}};
            send_phase    <= 3'd0;
            send_done     <= 1'b0;
            tx_start      <= 1'b0;
            wait_tx_done  <= 1'b0;
            tx_data       <= 8'h00;
            done          <= 1'b0;
        end else begin
            state <= next_state;
            // hold tx_start unless cleared below; ensures uart_tx sees the pulse
            tx_start <= tx_start;
            done     <= 1'b0;

            case (state)
                IDLE: begin
                    idx           <= {ADDR_WIDTH{1'b0}};
                    col           <= 3'd0;
                    send_phase    <= 3'd0;
                    send_done     <= 1'b0;
                    tx_start      <= 1'b0;
                    wait_tx_done  <= 1'b0;
                end

                LOAD: begin
                    // prepare for new element
                    send_phase    <= 3'd0;
                    send_done     <= 1'b0;
                    tx_start      <= 1'b0;
                    wait_tx_done  <= 1'b0;
                end

                FORMAT: begin
                    // slice current element from packed input (row-major)
                    val_reg <= matrix_flat[(idx*ELEM_WIDTH) +: ELEM_WIDTH];
                end

                SEND: begin
                    if (!wait_tx_done && !tx_busy && !send_done) begin
                        // 发送当前字节
                        tx_data      <= send_byte;
                        tx_start     <= 1'b1;
                        wait_tx_done <= 1'b1;
                    end else if (wait_tx_done && tx_busy) begin
                        // uart_tx已响应，清除start
                        tx_start <= 1'b0;
                    end else if (wait_tx_done && !tx_busy && tx_start == 1'b0) begin
                        // uart_tx完成发送（tx_busy回落），准备下一个字节
                        wait_tx_done <= 1'b0;
                        if (send_phase == send_phase_max) begin
                            send_done <= 1'b1;
                        end else begin
                            send_phase <= send_phase + 1'b1;
                        end
                    end
                end

                ADVANCE: begin
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


