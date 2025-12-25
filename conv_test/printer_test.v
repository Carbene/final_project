`timescale 1ns / 1ps
// Convolution Result Printer (8x10, 16-bit elements, based on matrix_printer handshake)
// - Prints each 16-bit element as 4 right-aligned characters: [space][hundreds][tens][ones]
// - Rows end with CRLF ("\r\n")
// - Input packed matrix_flat: 80 elements (row-major), element k at [k*16 +: 16]
// - Handshake: tx_start -> uart_tx_en, tx_busy from uart_tx

module conv_matrix_printer (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,               // start printing when high (level)
    input  wire [1279:0] matrix_flat,      // 80 * 16 bits
    input  wire        tx_busy,
    output reg         tx_start,           // drive uart_tx_en
    output reg  [7:0]  tx_data,            // drive uart_tx_data
    output reg         done                // pulses high when all sent
);

    localparam ROWS = 8;
    localparam COLS = 10;
    localparam TOTAL = ROWS * COLS; // 80
    localparam ELEM_WIDTH = 16;
    localparam PACKED_WIDTH = TOTAL * ELEM_WIDTH; // 1280

    localparam IDLE = 3'd0, LOAD = 3'd1, FORMAT = 3'd2, SEND = 3'd3, ADVANCE = 3'd4, DONE_S = 3'd5;

    reg  [2:0]              state, next_state;
    reg  [6:0]              idx;        // 0..79
    reg  [3:0]              col;        // 0..9
    reg  [ELEM_WIDTH-1:0]   val_reg;    // current element
    reg  [2:0]              send_phase; // 0..3 for element, then separator if col_last
    reg                     send_done;
    reg                     wait_tx_done;

    wire                    col_last;
    wire [3:0]              hundreds;
    wire [3:0]              tens;
    wire [3:0]              ones;
    wire [2:0]              digit_count;     // always 4: space + hundreds + tens + ones
    wire [2:0]              separator_len;   // 2 if col_last (CR LF), else 0
    wire [2:0]              send_count;
    wire [2:0]              send_phase_max;
    reg  [7:0]              send_byte;

    assign col_last = (col == COLS-1);

    // digit computations (elements < 1000)
    assign hundreds = (val_reg >= 16'd100) ? (val_reg / 16'd100) : 4'd0;
    assign tens     = ((val_reg % 16'd100) >= 16'd10) ? ((val_reg % 16'd100) / 16'd10) : 4'd0;
    assign ones     = (val_reg % 16'd10);

    assign digit_count    = 3'd4; // fixed: space, hundreds/space, tens/space, ones
    assign separator_len  = col_last ? 3'd2 : 3'd0; // CR LF if last col
    assign send_count     = digit_count + separator_len;
    assign send_phase_max = send_count - 1'b1;

    // choose byte based on phase
    always @(*) begin
        if (send_phase < digit_count) begin
            case (send_phase)
                3'd0: send_byte = 8'h20; // space
                3'd1: send_byte = (val_reg >= 16'd100) ? (8'd48 + hundreds) : 8'h20; // hundreds or space
                3'd2: send_byte = ((val_reg % 16'd100) >= 16'd10) ? (8'd48 + tens) : 8'h20; // tens or space
                3'd3: send_byte = 8'd48 + ones; // ones
                default: send_byte = 8'h20;
            endcase
        end else begin
            // separator: CR LF
            send_byte = (send_phase == digit_count) ? 8'h0D : 8'h0A; // \r then \n
        end
    end

    // next state
    always @(*) begin
        next_state = state;
        case (state)
            IDLE:     next_state = start ? LOAD : IDLE;
            LOAD:     next_state = (idx >= TOTAL) ? DONE_S : FORMAT;
            FORMAT:   next_state = SEND;
            SEND:     next_state = send_done ? ADVANCE : SEND;
            ADVANCE:  next_state = ((idx + 1'b1 >= TOTAL) ? DONE_S : LOAD);
            DONE_S:   next_state = start ? DONE_S : IDLE;
            default:  next_state = IDLE;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    // sequential
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            idx           <= 7'd0;
            col           <= 4'd0;
            val_reg       <= {ELEM_WIDTH{1'b0}};
            send_phase    <= 3'd0;
            send_done     <= 1'b0;
            tx_start      <= 1'b0;
            wait_tx_done  <= 1'b0;
            tx_data       <= 8'h00;
            done          <= 1'b0;
        end else begin
            state <= next_state;
            tx_start <= tx_start; // hold unless cleared
            done     <= 1'b0;

            case (state)
                IDLE: begin
                    idx           <= 7'd0;
                    col           <= 4'd0;
                    send_phase    <= 3'd0;
                    send_done     <= 1'b0;
                    tx_start      <= 1'b0;
                    wait_tx_done  <= 1'b0;
                end

                LOAD: begin
                    send_phase    <= 3'd0;
                    send_done     <= 1'b0;
                    tx_start      <= 1'b0;
                    wait_tx_done  <= 1'b0;
                end

                FORMAT: begin
                    val_reg <= matrix_flat[(idx*ELEM_WIDTH) +: ELEM_WIDTH];
                end

                SEND: begin
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

                ADVANCE: begin
                    if (idx + 1'b1 < TOTAL) begin
                        idx <= idx + 1'b1;
                        if (col_last) begin
                            col <= 4'd0;
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