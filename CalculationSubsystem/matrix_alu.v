//==============================================================================
// 矩阵ALU模块 (带流水线的矩阵乘法优化)
//==============================================================================
module matrix_alu (
    input wire clk,
    input wire rst_n,
    input wire [2:0] op_code,
    input wire start,
    
    // 矩阵A输入 (压缩格式)
    input wire [199:0] matrix_a_flat,
    input wire [2:0] m_a,
    input wire [2:0] n_a,
    
    // 矩阵B输入 (压缩格式)
    input wire [199:0] matrix_b_flat,
    input wire [2:0] m_b,
    input wire [2:0] n_b,
    
    // 标量输入
    input wire [7:0] scalar,
    
    // 结果输出
    output reg [399:0] result_flat,
    output reg [2:0] result_m,
    output reg [2:0] result_n,
    output reg done,
    output reg valid,
    output reg busy
);

// 运算类型定义
localparam OP_TRANSPOSE = 3'd0;
localparam OP_SCALAR    = 3'd1;
localparam OP_ADD       = 3'd2;
localparam OP_MULTIPLY  = 3'd3;

// 状态机
localparam IDLE    = 2'd0;
localparam COMPUTE = 2'd1;
localparam FINISH  = 2'd2;

reg [1:0] state;
reg [2:0] i, j;
reg [3:0] k;                // 4bit 以覆盖乘法循环
reg [15:0] temp_sum;
reg [2:0] m_len, n_len;     // 锁存的A矩阵尺寸，防止运算中尺寸被清空
reg [2:0] mb_len;          // 锁存的B矩阵行数（用于乘法）
reg [2:0] nb_len;           // 锁存的B矩阵列数（用于乘法）


// ✅ 新增：流水线寄存器
reg [15:0] mult_result_pipe1;
reg [15:0] sum_pipe2;
reg        valid_pipe1, valid_pipe2;

// 辅助信号：提取矩阵元素
wire [7:0] a_elem, b_elem;
// 依据锁存的实际列数进行索引，紧凑行优先打包（与打印模块一致）
assign a_elem = matrix_a_flat[((i)*n_len+(j))*8 +: 8];
assign b_elem = matrix_b_flat[((i)*n_len+(j))*8 +: 8];

// 用于矩阵乘法的元素访问
wire [7:0] a_ik, b_kj;
assign a_ik = (k[2:0] < n_len) ? matrix_a_flat[((i)*n_len+(k[2:0]))*8 +: 8] : 8'd0;
assign b_kj = (k[2:0] < mb_len) ? matrix_b_flat[((k[2:0])*nb_len+(j))*8 +: 8] : 8'd0;

// 临时计算 wire（块外声明）
wire [15:0] add_tmp, scalar_tmp, mul_tmp;
assign add_tmp = {8'd0, a_elem} + {8'd0, b_elem};
assign scalar_tmp = a_elem * scalar;
assign mul_tmp = a_ik * b_kj;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
        done <= 1'b0;
        valid <= 1'b1;
        i <= 3'd0;
        j <= 3'd0;
        k <= 3'd0;
        temp_sum <= 16'd0;
        mb_len <= 3'd0;
        nb_len <= 3'd0;
        result_flat <= 400'd0;
        result_m <= 3'd0;
        result_n <= 3'd0;
        m_len <= 3'd0;
        n_len <= 3'd0;
        // ✅ 复位流水线寄存器
        mult_result_pipe1 <= 16'd0;
        sum_pipe2 <= 16'd0;
        valid_pipe1 <= 1'b0;
        valid_pipe2 <= 1'b0;
    end else begin
        case (state)
            IDLE: begin
                done <= 1'b0;
                busy <= 1'b0;
                if (start) begin
                    // 检查运算数合法性
                    case (op_code)
                        OP_TRANSPOSE: valid <= m_a >= 3'd0 && n_a >= 3'd0 && m_a <= 3'd5 && n_a <= 3'd5;
                        OP_ADD:       valid <= (m_a == m_b) && (n_a == n_b) && m_a >= 3'd0 && n_a >= 3'd0 && m_a <= 3'd5 && n_a <= 3'd5;
                        OP_SCALAR:    valid <= m_a >= 3'd0 && n_a >= 3'd0 && m_a <= 3'd5 && n_a <= 3'd5;
                        OP_MULTIPLY:  valid <= (n_a == m_b) && m_a >= 3'd0 && n_a >= 3'd0 && m_b >= 3'd0 && n_b >= 3'd0 &&
                                              m_a <= 3'd5 && n_a <= 3'd5 && m_b <= 3'd5 && n_b <= 3'd5;
                        default:      valid <= 1'b0;
                    endcase
                    
                    busy <= 1'b1;
                    state <= COMPUTE;
                    i <= 3'd0;
                    j <= 3'd0;
                    k <= 4'd0;
                    temp_sum <= 16'd0;
                    // 锁存尺寸，避免上层在运算期间清空导致仅首行被计算
                    m_len <= m_a;
                    n_len <= n_a;
                    mb_len <= m_b;
                    nb_len <= n_b;
                end
            end
            
            COMPUTE: begin
                if (!valid) begin
                    state <= FINISH;
                end else begin
                    case (op_code)
                        OP_TRANSPOSE: begin
                            // result[j][i] = a[i][j]，输出16位存储以匹配matrix_printer16，紧凑打包
                            result_flat[((j)*m_len+(i))*16 +: 16] <= {8'd0, a_elem};
                            
                            if (j == n_len - 1) begin
                                j <= 3'd0;
                                if (i == m_len - 1) begin
                                    result_m <= n_len;
                                    result_n <= m_len;
                                    state <= FINISH;
                                end else begin
                                    i <= i + 1'b1;
                                end
                            end else begin
                                j <= j + 1'b1;
                            end
                        end
                        
                        OP_ADD: begin
                            // 加法结果16位存储以匹配matrix_printer16（饱和255），紧凑打包
                            result_flat[((i)*n_len+(j))*16 +: 16] <= (add_tmp > 16'd255) ? 16'd255 : add_tmp;
                            
                            if (j == n_len - 1) begin
                                j <= 3'd0;
                                if (i == m_len - 1) begin
                                    result_m <= m_len;
                                    result_n <= n_len;
                                    state <= FINISH;
                                end else begin
                                    i <= i + 1'b1;
                                end
                            end else begin
                                j <= j + 1'b1;
                            end
                        end
                        
                        OP_SCALAR: begin
                            // 标量乘法16位存储以匹配matrix_printer16（饱和255），紧凑打包
                            result_flat[((i)*n_len+(j))*16 +: 16] <= (scalar_tmp > 16'd255) ? 16'd255 : scalar_tmp;
                            
                            if (j == n_len - 1) begin
                                j <= 3'd0;
                                if (i == m_len - 1) begin
                                    result_m <= m_len;
                                    result_n <= n_len;
                                    state <= FINISH;
                                end else begin
                                    i <= i + 1'b1;
                                end
                            end else begin
                                j <= j + 1'b1;
                            end
                        end
                        
                        // ✅ 矩阵乘法：逐拍累加，避免流水线阶段丢失首项
                        OP_MULTIPLY: begin
                            if (k < n_len) begin
                                if (k == 4'd0)
                                    temp_sum <= a_ik * b_kj;          // 首项直接赋值
                                else
                                    temp_sum <= temp_sum + a_ik * b_kj; // 后续累加

                                k <= k + 1'b1;
                            end else begin
                                // 结果存储阶段：矩阵乘法16位存储以匹配matrix_printer16（饱和255），紧凑打包
                                result_flat[((i)*nb_len+(j))*16 +: 16] <= temp_sum;

                                k <= 4'd0;
                                temp_sum <= 16'd0;

                                if (j == nb_len - 1) begin
                                    j <= 3'd0;
                                    if (i == m_len - 1) begin
                                        result_m <= m_len;
                                        result_n <= nb_len;
                                        state <= FINISH;
                                    end else begin
                                        i <= i + 1'b1;
                                    end
                                end else begin
                                    j <= j + 1'b1;
                                end
                            end
                        end
                        
                        default: state <= FINISH;
                    endcase
                end
            end
            
            FINISH: begin
                done <= 1'b1;
                busy <= 1'b0;
                state <= IDLE;
            end
            
            default: state <= IDLE;
        endcase
    end
end

endmodule