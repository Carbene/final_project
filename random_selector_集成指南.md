# 随机选择模块与计算系统集成指南

## 概览

随机选择模块 (`random_selector.v`) 为计算子系统提供自动操作数选择功能。该模块无需用户手动选择矩阵，而是通过 LFSR 随机数生成器自动从存储器中选择符合条件的矩阵。

## 系统架构

```
┌─────────────────────────────────────────┐
│      Calculator Subsystem               │
│  ┌──────────────────────────────────┐   │
│  │   State Machine                  │   │
│  │ (WAIT_INPUT_MODE)                │   │
│  └──────────────────────────────────┘   │
│                   │                      │
│        ┌──────────┴──────────┐           │
│        │                     │           │
│        ▼ (手动mode)          ▼ (自动mode)│
│   ┌─────────────┐     ┌─────────────┐   │
│   │  selector_  │     │   random_   │   │
│   │  display    │     │  selector   │   │
│   └─────────────┘     └─────────────┘   │
│                            │             │
│        ┌───────────────────┘             │
│        │                                 │
│        ▼                                 │
│   ┌─────────────┐                       │
│   │    ALU /    │                       │
│   │ Calculation │                       │
│   └─────────────┘                       │
└─────────────────────────────────────────┘
```

## 工作流程

### 手动模式 (input_mode_reg = 1)

```
WAIT_INPUT_MODE
    ↓ (btn_confirm, input_mode_reg = 1)
OP1_SEL
    ↓ (selector_display 工作)
    用户通过 uart 手动选择第一个操作数
    ↓
OP1_WAIT
    ↓ (selector_done)
BRANCH_OP
    ↓ (根据操作类型)
    单目 → VALIDATION
    双目 → OP2_SEL
           ↓ (selector_display 工作)
           用户通过 uart 手动选择第二个操作数
           ↓
           OP2_WAIT → VALIDATION → EXECUTE
```

### 自动模式 (input_mode_reg = 0)

```
WAIT_INPUT_MODE
    ↓ (btn_confirm, input_mode_reg = 0)
OP1_SEL
    ↓ (random_selector 启动)
GEN_RAND_OP1
    ↓ (生成随机位置)
QUERY_OP1 → CHECK_OP1_EXISTS
    ├─ (无有效矩阵，重试 < 50)
    │   └─ → GEN_RAND_OP1
    └─ (有有效矩阵)
        └─ → READ_OP1 → PRINT_OP1 → PRINT_OP1_WAIT
            ↓ (打印完成，print_done)
            ▼
        BRANCH_OP
            ↓ (根据操作类型)
            单目 (转置/标量) → VALIDATION
            双目 (加法/乘法) → GEN_RAND_OP2
                              ↓ (同上逻辑选择第二个操作数)
                              READ_OP2 → PRINT_OP2 → PRINT_OP2_WAIT
                                        ↓ (打印完成)
                                        VALIDATION
        VALIDATION → EXECUTE
```

## 修改计算模块的步骤

### 步骤 1：在 calculator_subsystem.v 中实例化 random_selector

在模块声明部分添加：

```verilog
random_selector u_random_selector (
    .clk(clk),
    .rst_n(rst_n),
    .enable(enable_random),         // 自动模式启用信号
    .op_code(op_code_reg[1:0]),    // 操作码
    .info_table(info_table),         // 来自存储模块
    .query_index(query_index),
    .query_dim_m(query_dim_m),
    .query_dim_n(query_dim_n),
    .read_en(random_read_en),        // 存储读请求
    .rd_col(random_rd_col),
    .rd_row(random_rd_row),
    .rd_mat_index(random_rd_mat_index),
    .rd_data_flow(store_rd_data_flow),
    .rd_ready(store_rd_ready),
    .sel_dim_m(random_sel_dim_m),   // 选中矩阵信息
    .sel_dim_n(random_sel_dim_n),
    .sel_matrix(random_sel_matrix),
    .sel_matrix_id(random_sel_matrix_id),
    .sel_done(random_sel_done),
    .sel_error(random_sel_error),
    .print_start(random_print_start), // 矩阵打印请求
    .print_dim_m(random_print_dim_m),
    .print_dim_n(random_print_dim_n),
    .print_matrix(random_print_matrix),
    .print_done(print_done)         // 来自矩阵打印模块
);
```

### 步骤 2：修改状态机

在 `WAIT_INPUT_MODE` 状态后添加条件分支：

```verilog
OP1_SEL: begin
    case (input_mode_reg)
        1'b1: begin
            // 手动模式：使用 selector_display
            selector_en <= 1'b1;
        end
        1'b0: begin
            // 自动模式：使用 random_selector
            // random_selector 内部自动启动
        end
    endcase
    retry_target <= OP1_SEL;
end

OP1_WAIT: begin
    if (input_mode_reg) begin
        // 手动模式：等待 selector_display
        if (selector_done) begin
            matrix_a_flat <= matrix;
            m_a <= dim_m;
            n_a <= dim_n;
            next_state = BRANCH_OP;
        end else if (selector_error) begin
            next_state = ERROR;
        end
    end else begin
        // 自动模式：等待 random_selector
        if (random_sel_done) begin
            matrix_a_flat <= random_sel_matrix;
            m_a <= random_sel_dim_m;
            n_a <= random_sel_dim_n;
            next_state = BRANCH_OP;
        end else if (random_sel_error) begin
            next_state = ERROR;
        end
    end
end
```

类似地修改 `OP2_SEL` 和 `OP2_WAIT` 状态。

### 步骤 3：处理存储访问仲裁

由于 selector_display 和 random_selector 都需要访问存储，需要添加仲裁逻辑：

```verilog
// 仲裁逻辑：优先使用 random_selector（在自动模式下）
wire arbiter_read_en = input_mode_reg ? selector_read_en : random_read_en;
wire [2:0] arbiter_rd_col = input_mode_reg ? selector_rd_col : random_rd_col;
wire [2:0] arbiter_rd_row = input_mode_reg ? selector_rd_row : random_rd_row;
wire [1:0] arbiter_rd_mat_index = input_mode_reg ? selector_rd_mat_index : random_rd_mat_index;

// 连接到 matrix_storage
matrix_storage u_store (
    .clk(clk),
    .rst_n(rst_n),
    // ...
    .read_en(arbiter_read_en),
    .rd_col(arbiter_rd_col),
    .rd_row(arbiter_rd_row),
    .rd_mat_index(arbiter_rd_mat_index),
    .rd_data_flow(store_rd_data_flow),
    .rd_ready(store_rd_ready),
    // ...
);
```

### 步骤 4：处理矩阵打印通道仲裁

同样需要仲裁来自两个选择器的打印请求：

```verilog
// 打印优先级：如果是自动模式且有打印请求，优先使用 random_selector 的打印
wire arbiter_print_start = input_mode_reg ? selector_print_start : random_print_start;
wire [2:0] arbiter_print_dim_m = input_mode_reg ? selector_print_dim_m : random_print_dim_m;
wire [2:0] arbiter_print_dim_n = input_mode_reg ? selector_print_dim_n : random_print_dim_n;
wire [199:0] arbiter_print_matrix = input_mode_reg ? selector_print_matrix : random_print_matrix;

matrix_printer u_print_for_selector (
    .clk(clk),
    .rst_n(rst_n),
    .start(arbiter_print_start),
    .matrix_flat(arbiter_print_matrix),
    .dimM(arbiter_print_dim_m),
    .dimN(arbiter_print_dim_n),
    .use_crlf(1'b1),
    .tx_start(uart_tx_en_selector),
    .tx_data(uart_tx_data_selector),
    .tx_busy(uart_tx_busy),
    .done(print_done)
);
```

## 维度验证逻辑

### 加法验证

两个矩阵维度必须完全相同：

```
选择第二个矩阵时，random_selector 需要检查：
m1 == m2 && n1 == n2

例如：
第一个矩阵：3x4
第二个矩阵需要：也是 3x4
```

在 random_selector 中修改 CHECK_OP2_VALID：

```verilog
CHECK_OP2_VALID: begin
    if (op2_count != 2'd0) begin
        op2_m <= op2_pos / 5'd5;
        op2_n <= op2_pos % 5'd5;
        
        // 检查是否满足运算规则
        case (op_code)
            OP_ADD: begin
                if ((op2_pos / 5'd5 == op1_m) && (op2_pos % 5'd5 == op1_n))
                    next_state = READ_OP2;
                else if (retry_count < MAX_RETRY)
                    next_state = GEN_RAND_OP2;
                else
                    next_state = ERROR;
            end
            OP_MUL: begin
                if ((op2_pos / 5'd5) == op1_n)  // 第二个矩阵的行数 = 第一个的列数
                    next_state = READ_OP2;
                else if (retry_count < MAX_RETRY)
                    next_state = GEN_RAND_OP2;
                else
                    next_state = ERROR;
            end
            // ...
        endcase
    end
end
```

### 矩阵乘法验证

第一个矩阵的列数必须等于第二个矩阵的行数：

```
例如：
第一个矩阵：3x4 (3行4列)
第二个矩阵需要：4xN (行数为 4)

即：n1 (4) == m2 (4)
```

## 测试用例

### 测试 1：自动转置

```
1. 开关选择：操作码 = 转置，输入模式 = 自动
2. random_selector 生成随机位置，假设位置 7 (2x3)
3. 读取 2x3 矩阵，打印
4. 直接进入 EXECUTE，执行转置
5. 结果维度：3x2
```

### 测试 2：自动加法

```
1. 开关选择：操作码 = 加法，输入模式 = 自动
2. random_selector 生成随机位置，假设位置 12 (3x3)
3. 读取第一个 3x3 矩阵，打印
4. random_selector 再次生成随机位置
5. 检查维度：需要也是 3x3
   - 如果不是，继续生成直到找到 3x3 矩阵
   - 最多尝试 50 次
6. 读取第二个 3x3 矩阵，打印
7. 进入 EXECUTE，执行加法
```

### 测试 3：自动矩阵乘法 - 维度匹配

```
1. 开关选择：操作码 = 乘法，输入模式 = 自动
2. 第一个矩阵：3x4 (位置 8)
3. 需要找第二个矩阵：行数为 4 (即 4xN)
   - 位置 15-19 (4x1 至 4x5) 都是有效的
4. 假设找到位置 17 (4x3)
5. 执行 3x4 * 4x3 = 3x3 乘法
```

### 测试 4：无有效矩阵 - 错误处理

```
1. 假设存储为空（info_table = 0）
2. random_selector 无法找到任何矩阵
3. 尝试 50 次后进入 ERROR 状态
4. 计算模块接收 random_sel_error = 1
5. 转移到 ERROR 状态，触发倒计时
6. 返回 IDLE
```

## 性能考虑

| 项目 | 值 | 说明 |
|------|-----|------|
| LFSR 周期 | 2^32 - 1 | 非常长，不会重复 |
| 平均查询次数 | ~2-3 | 取决于存储器内容 |
| 最坏情况重试 | 50 | 防止无限循环 |
| 加法验证成功率 | 高 | 一旦第一个矩阵确定，第二个容易找到 |
| 乘法验证成功率 | 中等 | 需要特定维度 |

## 扩展建议

1. **可配置重试次数**: 根据存储器内容动态调整
2. **优先级加权**: 优先选择较常用的维度
3. **统计信息**: 记录选择过程中的重试次数和成功率
4. **种子设置**: 允许从外部设置 LFSR 初始种子以实现可重复的随机序列
5. **详细错误码**: 区分不同类型的选择失败

## 故障排查

### 问题：随机选择一直失败
- **可能原因 1**：存储器为空或特定维度无矩阵
- **解决方案**：检查 info_table，确保有足够的矩阵

### 问题：加法自动选择找不到匹配的第二个矩阵
- **可能原因 2**：第一个矩阵维度在存储器中是孤立的
- **解决方案**：向存储器添加相同维度的矩阵

### 问题：随机结果不同
- **原因**：LFSR 每个时钟周期都在进化，不启用模块时 LFSR 也在进化
- **解决方案**：若需要可重复结果，可冻结 LFSR 更新

## 下一步

1. 实现存储访问仲裁逻辑
2. 修改计算模块状态机
3. 集成到顶层模块
4. 进行仿真验证
5. 在 FPGA 上测试
