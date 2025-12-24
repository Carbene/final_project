//==============================================================================
// UART�������������׳�棩
// ����
// - ��ʽ "m n a_11 a_12 ... a_1m a_21 a_22 ... a_2n ... a_m1 a_m2 ... a_mn"
// - m,n ���� 1~5
// - Ԫ�ر��� 0~9����������
// - Ԫ�ز����Զ��� 0�����ֳ�ֵ0����������
// - Ԫ�س��� m*n ʱ���Ժ������룬���
// - ��ʱ��δ���� 5s ��������ʼ����� 0.5s ���м���β�����㲹�㣬��������ɣ�
//==============================================================================
module uart_parser (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] rx_data,
    input  wire       rx_done,
    input  wire       parse_enable,
    input  wire [7:0] elem_min,
    input  wire [7:0] elem_max,
    output reg  [2:0] parsed_m,
    output reg  [2:0] parsed_n,
    output reg  [199:0] parsed_matrix_flat,
    output reg        parse_done,
    output reg        parse_error
);

localparam IDLE       = 3'd0;
localparam PARSE_M    = 3'd1;
localparam PARSE_N    = 3'd2;
localparam PARSE_DATA = 3'd3;
localparam DONE       = 3'd4;
localparam ERROR      = 3'd5;

// ��ʱ���� (Ĭ��100MHzʱ��)
parameter integer CLK_FREQ_HZ         = 100_000_000;
localparam [31:0] IDLE_TIMEOUT_CYCLES = CLK_FREQ_HZ * 10;  // ����S2��δ��ʼ���룺10�볬ʱ
localparam [31:0] GAP_TIMEOUT_CYCLES  = CLK_FREQ_HZ * 2;   // ���������/���������ַ���2����β/��ʱ

reg [2:0]  state;
reg [4:0]  elem_index;
reg [7:0]  current_num;
reg        num_started;
reg [31:0] timeout_counter;
reg        seen_activity;
reg        target_reached;

wire [4:0] target_elems = parsed_m * parsed_n; // up to 25

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
        parsed_m <= 3'd0;
        parsed_n <= 3'd0;
        parsed_matrix_flat <= 200'd0;
        parse_done <= 1'b0;
        parse_error <= 1'b0;
        elem_index <= 5'd0;
        current_num <= 8'd0;
        num_started <= 1'b0;
        timeout_counter <= 32'd0;
        seen_activity <= 1'b0;
        target_reached <= 1'b0;
    end else begin
        if (state == IDLE) begin
            parse_done  <= 1'b0;
            parse_error <= 1'b0;
        end

        case (state)
            IDLE: begin
                if (parse_enable) begin
                    state <= PARSE_M;
                    elem_index <= 5'd0;
                    current_num <= 8'd0;
                    num_started <= 1'b0;
                    parsed_matrix_flat <= 200'd0; // Ԥ��Ϊ0�����ڲ��㲹��
                    parsed_m <= 3'd0;
                    parsed_n <= 3'd0;
                    timeout_counter <= 32'd0;
                    seen_activity <= 1'b0;
                    target_reached <= 1'b0;
                    parse_done <= 1'b0;  // �����ɱ�־
                    parse_error <= 1'b0; // ��������־
                end
            end

            PARSE_M: begin
                if (!parse_enable) begin
                    state <= IDLE;
                end else if (timeout_counter >= (seen_activity ? GAP_TIMEOUT_CYCLES : IDLE_TIMEOUT_CYCLES)) begin
                    parse_error <= 1'b1;
                    state <= ERROR;
                end else if (rx_done) begin
                    timeout_counter <= 32'd0;
                    seen_activity <= 1'b1;

                    if (rx_data >= "0" && rx_data <= "9") begin
                        current_num <= current_num * 10 + (rx_data - "0");
                        num_started <= 1'b1;
                    end else if (rx_data == 8'h20 && num_started) begin // �ո�ָ���
                        // m ��Χ 1~5
                        if (current_num >= 1 && current_num <= 5) begin
                            parsed_m <= current_num[2:0];
                            current_num <= 8'd0;
                            num_started <= 1'b0;
                            state <= PARSE_N;
                        end else begin
                            parse_error <= 1'b1;
                            state <= ERROR;
                        end
                    end else if (rx_data == 8'h20 || rx_data == 8'h0D || rx_data == 8'h0A) begin
                        // ����ǰ���ո�ͻ���
                    end else begin
                        parse_error <= 1'b1;
                        state <= ERROR;
                    end
                end else begin
                    timeout_counter <= timeout_counter + 1'b1;
                end
            end

            PARSE_N: begin
                if (!parse_enable) begin
                    state <= IDLE;
                end else if (timeout_counter >= (seen_activity ? GAP_TIMEOUT_CYCLES : IDLE_TIMEOUT_CYCLES)) begin
                    // ֻ����� m����Ϊ����
                    parse_error <= 1'b1;
                    state <= ERROR;
                end else if (rx_done) begin
                    timeout_counter <= 32'd0;
                    seen_activity <= 1'b1;

                    if (rx_data >= "0" && rx_data <= "9") begin
                        current_num <= current_num * 10 + (rx_data - "0");
                        num_started <= 1'b1;
                    end else if (rx_data == 8'h20 && num_started) begin // �ո�ָ���
                        // n ��Χ 1~5
                        if (current_num >= 1 && current_num <= 5) begin
                            parsed_n <= current_num[2:0];
                            current_num <= 8'd0;
                            num_started <= 1'b0;
                            state <= PARSE_DATA;
                        end else begin
                            parse_error <= 1'b1;
                            state <= ERROR;
                        end
                    end else if (rx_data == 8'h20 || rx_data == 8'h0D || rx_data == 8'h0A) begin
                        // ���Զ���ո�ͻ���
                    end else begin
                        parse_error <= 1'b1;
                        state <= ERROR;
                    end
                end else begin
                    timeout_counter <= timeout_counter + 1'b1;
                end
            end

            PARSE_DATA: begin
                if (!parse_enable) begin
                    state <= IDLE;
                end else if (timeout_counter >= (seen_activity ? GAP_TIMEOUT_CYCLES : IDLE_TIMEOUT_CYCLES)) begin
                    // ��β���������������һ�������ȴ��룻���������0
                    if (num_started && !target_reached && (elem_index < target_elems)) begin
                        parsed_matrix_flat[elem_index*8 +: 8] <= current_num;
                        elem_index <= elem_index + 1'b1;
                    end
                    parse_done <= 1'b1;
                    state <= DONE;
                    target_reached <= 1'b1;
                end else if (rx_done) begin
                    timeout_counter <= 32'd0;
                    seen_activity <= 1'b1;

                    if (target_reached) begin
                        // �Ѵ����ޣ����Ժ�������
                        parse_done <= 1'b1;
                        state <= DONE;
                    end else if (rx_data >= "0" && rx_data <= "9") begin
                        // ���Ԫ�ط�Χ (ʹ��elem_min��elem_max)
                        // �������֣�ֱ���ۼ�
                        if (num_started) begin
                            // �Ѿ���ʼ�������֣������ֵ�Ƿ��ڷ�Χ��
                            if (current_num * 10 + (rx_data - "0") <= elem_max) begin
                                current_num <= current_num * 10 + (rx_data - "0");
                            end else begin
                                // ������Χ������
                                parse_error <= 1'b1;
                                state <= ERROR;
                            end
                        end else begin
                            // ��һ������
                            current_num <= rx_data - "0";
                            num_started <= 1'b1;
                        end
                    end else if ((rx_data == 8'h20 || rx_data == 8'h0D || rx_data == 8'h0A) && num_started) begin
                        // ���һ��Ԫ��
                        if (elem_index < target_elems) begin
                            parsed_matrix_flat[elem_index*8 +: 8] <= current_num;
                            elem_index <= elem_index + 1'b1;
                            current_num <= 8'd0;
                            num_started <= 1'b0;

                            if (elem_index + 1 == target_elems) begin
                                parse_done <= 1'b1;
                                state <= DONE;
                                target_reached <= 1'b1;
                            end
                        end else begin
                            // �������ޣ����Ժ���
                            parse_done <= 1'b1;
                            state <= DONE;
                            target_reached <= 1'b1;
                        end
                    end else if (rx_data == 8'h20 || rx_data == 8'h0D || rx_data == 8'h0A) begin
                        // ���Զ���Ŀո񡢻س�������
                    end else begin
                        // �Ƿ��ַ�
                        parse_error <= 1'b1;
                        state <= ERROR;
                    end
                end else begin
                    timeout_counter <= timeout_counter + 1'b1;
                end
            end

            DONE: begin
                if (!parse_enable) state <= IDLE;
            end

            ERROR: begin
                if (!parse_enable) state <= IDLE;
            end

            default: state <= IDLE;
        endcase
    end
end

endmodule