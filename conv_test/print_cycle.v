`timescale 1ns / 1ps
// Print Cycles Module: prints the cycles_counter as decimal digits + \r\n
// Starts only after matrix print is done (start=1)

module print_cycles (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,        // start when matrix print done
    input  wire [15:0] cycles,       // cycles_counter from engine
    input  wire        tx_busy,
    output reg         tx_start,     // drive uart_tx_en
    output reg  [7:0]  tx_data,      // drive uart_tx_data
    output reg         done          // pulses high when done
);

    localparam IDLE = 3'd0, SEND = 3'd1, ADVANCE = 3'd2, DONE_S = 3'd3;

    reg  [2:0] state, next_state;
    reg  [2:0] send_phase; // 0: hundreds, 1: tens, 2: ones, 3: \r, 4: \n
    reg        send_done;
    reg        wait_tx_done;

    wire [3:0] hundreds = (cycles >= 16'd100) ? (cycles / 16'd100) : 4'd0;
    wire [3:0] tens     = ((cycles % 16'd100) >= 16'd10) ? ((cycles % 16'd100) / 16'd10) : 4'd0;
    wire [3:0] ones     = cycles % 16'd10;
    wire [2:0] send_count = 3'd5; // hundreds, tens, ones, \r, \n
    wire [2:0] send_phase_max = send_count - 1'b1;

    // choose byte
    always @(*) begin
        case (send_phase)
            3'd0: tx_data = 8'd48 + hundreds;
            3'd1: tx_data = 8'd48 + tens;
            3'd2: tx_data = 8'd48 + ones;
            3'd3: tx_data = 8'd13; // \r
            3'd4: tx_data = 8'd10; // \n
            default: tx_data = 8'd48;
        endcase
    end

    always @(*) begin
        next_state = state;
        case (state)
            IDLE:     next_state = start ? SEND : IDLE;
            SEND:     next_state = send_done ? ADVANCE : SEND;
            ADVANCE:  next_state = (send_phase == send_phase_max) ? DONE_S : SEND;
            DONE_S:   next_state = start ? DONE_S : IDLE;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else state <= next_state;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            send_phase    <= 3'd0;
            send_done     <= 1'b0;
            tx_start      <= 1'b0;
            wait_tx_done  <= 1'b0;
            done          <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                IDLE: begin
                    send_phase    <= 3'd0;
                    send_done     <= 1'b0;
                    tx_start      <= 1'b0;
                    wait_tx_done  <= 1'b0;
                end
                SEND: begin
                    if (!wait_tx_done && !tx_busy && !send_done) begin
                        tx_start     <= 1'b1;
                        wait_tx_done <= 1'b1;
                    end else if (wait_tx_done && tx_busy) begin
                        tx_start <= 1'b0;
                    end else if (wait_tx_done && !tx_busy && tx_start == 1'b0) begin
                        wait_tx_done <= 1'b0;
                        send_done    <= 1'b1;
                    end
                end
                ADVANCE: begin
                    send_phase <= send_phase + 1'b1;
                    send_done  <= 1'b0;
                end
                DONE_S: begin
                    done <= 1'b1;
                end
            endcase
        end
    end

endmodule