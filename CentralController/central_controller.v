module Central_Controller (
    input clk,
    input rst_n,
    input [2:0] command,
    input btn_confirm,
    input btn_exit,

    input input_mode_exitable,
    output reg data_input_mode_en,
    input generate_mode_exitable,
    output reg generate_mode_en,
    input display_mode_exitable,
    output reg display_mode_en,
    input calculation_mode_exitable,
    output reg calculation_mode_en
);

    localparam MODE_IDLE = 3'd00;
    localparam MODE_DATA_INPUT  = 3'd01;
    localparam MODE_GENERATE    = 3'd02;
    localparam MODE_DISPLAY     = 3'd03;
    localparam MODE_CALCULATION = 3'd04;
    reg [2:0] current_mode, next_mode;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            current_mode <= MODE_IDLE;
        else
            current_mode <= next_mode;
    end 
    always @(*) begin
        case(current_mode)
            MODE_IDLE: begin
                if (btn_confirm) begin
                    case(command)
                        3'd1: next_mode = MODE_DATA_INPUT;   // '1'
                        3'd2: next_mode = MODE_GENERATE;     // '2'
                        3'd3: next_mode = MODE_DISPLAY;      // '3'
                        3'd4: next_mode = MODE_CALCULATION;  // '4'
                        3'd0: next_mode = MODE_IDLE;         // '0'
                        3'd5: next_mode = MODE_IDLE;         // '5' reserved for settings mode
                        3'd6: next_mode = MODE_IDLE;         // '6' reserved for future use
                        3'd7: next_mode = MODE_IDLE;         // '7' reserved for
                    endcase
                end else begin
                    next_mode = MODE_IDLE;
                end
            end
            MODE_DATA_INPUT: begin
                if (btn_exit|| (input_mode_exitable&& btn_confirm))
                    next_mode = MODE_IDLE;
                else
                    next_mode = MODE_DATA_INPUT;
            end
            MODE_GENERATE: begin
                if (btn_exit|| (generate_mode_exitable&& btn_confirm))
                    next_mode = MODE_IDLE;
                else
                    next_mode = MODE_GENERATE;
            end
            MODE_DISPLAY: begin
                if (btn_exit|| (display_mode_exitable&& btn_confirm))
                    next_mode = MODE_IDLE;
                else
                    next_mode = MODE_DISPLAY;
                
            end
            MODE_CALCULATION: begin
                if (btn_exit|| (calculation_mode_exitable&& btn_confirm))
                    next_mode = MODE_IDLE;
                else
                    next_mode = MODE_CALCULATION;
            end
            default: next_mode = MODE_IDLE;
        endcase
    end
    always@(*) begin
        data_input_mode_en   = 1'b0;
        generate_mode_en     = 1'b0;
        display_mode_en      = 1'b0;
        calculation_mode_en  = 1'b0;
        case(current_mode)
            MODE_DATA_INPUT:   data_input_mode_en   = 1'b1;
            MODE_GENERATE:     generate_mode_en     = 1'b1;
            MODE_DISPLAY:      display_mode_en      = 1'b1;
            MODE_CALCULATION:  calculation_mode_en  = 1'b1;
            default: ; // do nothing
        endcase
    end
endmodule