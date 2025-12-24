# 随机选择模块 (Random Selector) 使用说明

## 模块概述

`random_selector` 模块实现了随机矩阵选择功能，用于计算子系统的自动模式。该模块包含以下核心功能：

1. **LFSR 随机数生成**: 每个时钟周期生成一个新的随机数
2. **位置查询**: 检查随机位置是否有有效的矩阵元素
3. **维度验证**: 对于双目运算符，验证两个操作数的维度是否满足运算规则
4. **矩阵打印**: 将选中的操作数矩阵输出到打印模块
5. **重试机制**: 如果位置无效，自动重新生成随机位置（最多重试 50 次）

## 操作码定义

```
OP_TRANSPOSE = 3'd0    // 转置（单目）
OP_ADD       = 3'd1    // 加法（双目）
OP_SCALAR    = 3'd2    // 标量乘法（单目）
OP_MUL       = 3'd3    // 矩阵乘法（双目）
```

## 端口详解

### 控制信号
- **enable**: 启用随机选择模块
- **op_code[2:0]**: 操作码，用于判断是否需要选择第二个操作数

### 矩阵存储接口
- **info_table[49:0]**: 矩阵信息表
  - 格式：每个位置占 2 bit，表示该维度下有几个矩阵（0-3）
  - 总共 25 个位置（5x5 矩阵维度组合）
  - 位置计算：`place = (m-1)*5 + (n-1)` 其中 m,n ∈ [1,5]

### 查询接口
- **query_index[1:0]**: 查询矩阵槽位（0 或 1）
- **query_dim_m[2:0]**: 查询的维度行数
- **query_dim_n[2:0]**: 查询的维度列数

### 存储读接口
- **read_en**: 读取使能
- **rd_col, rd_row**: 读取维度坐标
- **rd_mat_index[1:0]**: 读取的矩阵槽位
- **rd_data_flow[199:0]**: 读回的矩阵数据
- **rd_ready**: 读数据有效

### 输出接口（给计算模块）
- **sel_dim_m, sel_dim_n**: 选中矩阵的维度
- **sel_matrix[199:0]**: 选中的矩阵数据
- **sel_matrix_id[1:0]**: 矩阵来自槽位 0 还是 1
- **sel_done**: 选择完成信号
- **sel_error**: 选择错误信号（无法找到有效矩阵）

### 打印接口（给矩阵打印模块）
- **print_start**: 启动打印
- **print_dim_m, print_dim_n**: 打印的矩阵维度
- **print_matrix[199:0]**: 打印的矩阵数据
- **print_done**: 打印完成信号

## 工作流程

### 单目运算（转置、标量乘法）

```
IDLE
  ↓ (enable = 1)
GEN_RAND_OP1
  ↓ (生成随机位置)
QUERY_OP1
  ↓ (查询该位置)
CHECK_OP1_EXISTS
  ├─ (有元素) → READ_OP1 → PRINT_OP1 → PRINT_OP1_WAIT
  └─ (无元素) → GEN_RAND_OP1 (重试，最多 50 次)
                  ↓ (超过重试次数)
                 ERROR
  ↓ (打印完成)
DONE → IDLE
```

### 双目运算（加法、矩阵乘法）- 手动模式

在计算模块的手动模式下，两个操作数分别由用户选择。

### 双目运算 - 自动模式

```
IDLE
  ↓ (enable = 1)
GEN_RAND_OP1 → QUERY_OP1 → CHECK_OP1_EXISTS → READ_OP1 
  ↓ (op_code = ADD or MUL)
PRINT_OP1 → PRINT_OP1_WAIT
  ↓ (打印完成)
GEN_RAND_OP2 → QUERY_OP2 → CHECK_OP2_VALID
  ├─ (有元素且满足运算规则) → READ_OP2 → PRINT_OP2 → PRINT_OP2_WAIT
  └─ (无元素或不满足) → GEN_RAND_OP2 (重试)
                          ↓ (超过重试次数)
                         ERROR
  ↓ (打印完成)
DONE → IDLE
```

## 关键功能说明

### 1. LFSR 随机数生成器

使用 32 bit Gallois 配置 LFSR，反馈多项式为 `x^32 + x^30 + x^26 + x^25 + 1`。

每个时钟周期生成一个新的随机数，通过模 25 运算得到矩阵位置（0-24）。

```verilog
// 位置转换
位置 i (0-24) → m = i / 5, n = i % 5
例如：位置 7 → m = 1, n = 2 (即 2x3 矩阵)
     位置 12 → m = 2, n = 2 (即 3x3 矩阵)
```

### 2. 维度到位置的映射

info_table 中共有 25 个位置，对应所有可能的矩阵维度：

```
位置 = (m-1) * 5 + (n-1)

m=1: 位置 0-4   (1x1, 1x2, 1x3, 1x4, 1x5)
m=2: 位置 5-9   (2x1, 2x2, 2x3, 2x4, 2x5)
m=3: 位置 10-14 (3x1, 3x2, 3x3, 3x4, 3x5)
m=4: 位置 15-19 (4x1, 4x2, 4x3, 4x4, 4x5)
m=5: 位置 20-24 (5x1, 5x2, 5x3, 5x4, 5x5)
```

### 3. 双目运算符合法性检查

#### 加法
- 要求：两个矩阵维度完全相同
- 验证：`m1 == m2 && n1 == n2`

#### 矩阵乘法
- 要求：第一个矩阵的列数 = 第二个矩阵的行数
- 验证：`n1 == m2`

### 4. 矩阵槽位选择

存储器中有两个矩阵槽位（0 和 1）。模块通过 info_table 判断该维度的矩阵存储在哪个槽位：

```verilog
// info_table 格式示例
info_table = 50'b...
// 位置 0（1x1）: info_table[1:0]  - 计数
// 位置 1（1x2）: info_table[3:2]  - 计数
// ...
// 位置 24（5x5）: info_table[49:48] - 计数

// 计数含义：
// 2'b00: 没有矩阵
// 2'b01: 只有槽位 0 有矩阵
// 2'b10: 只有槽位 1 有矩阵
// 2'b11: 两个槽位都有矩阵
```

### 5. 重试机制

- 每次生成无效位置时，自动重新生成
- 最多重试 50 次（MAX_RETRY = 8'd50）
- 如果 50 次后仍无有效位置，进入 ERROR 状态
- ERROR 状态下输出 `sel_error = 1`，计算模块应处理此错误

## 矩阵打印集成

模块会在选择完成前打印选中的矩阵：

1. **第一个操作数打印**: 在 PRINT_OP1 状态，输出 print_start = 1
2. **第二个操作数打印**: 在 PRINT_OP2 状态，输出 print_start = 1
3. 等待 print_done 信号后继续下一步

这样用户可以实时看到自动选择的操作数矩阵。

## 与计算模块的集成

### 在 calculator_subsystem 中的使用

```verilog
// 实例化随机选择模块
random_selector u_random_selector (
    .clk(clk),
    .rst_n(rst_n),
    .enable(enable_random_mode),
    .op_code(op_code_reg),
    .info_table(info_table),
    .query_index(query_index),
    .query_dim_m(query_dim_m),
    .query_dim_n(query_dim_n),
    .read_en(rand_read_en),
    .rd_col(rand_rd_col),
    .rd_row(rand_rd_row),
    .rd_mat_index(rand_rd_mat_index),
    .rd_data_flow(store_rd_data_flow),
    .rd_ready(store_rd_ready),
    .sel_dim_m(rand_sel_dim_m),
    .sel_dim_n(rand_sel_dim_n),
    .sel_matrix(rand_sel_matrix),
    .sel_matrix_id(rand_sel_matrix_id),
    .sel_done(rand_sel_done),
    .sel_error(rand_sel_error),
    .print_start(rand_print_start),
    .print_dim_m(rand_print_dim_m),
    .print_dim_n(rand_print_dim_n),
    .print_matrix(rand_print_matrix),
    .print_done(print_done)
);
```

在 BRANCH_OP 状态，根据 input_mode_reg 选择是否使用随机选择：

```verilog
BRANCH_OP: begin
    case (op_code_reg)
        OP_ADD, OP_MUL: begin
            if (input_mode_reg)
                // 手动模式：selector_display
                next_state = OP2_SEL;
            else
                // 自动模式：random_selector
                next_state = RANDOM_OP2_SEL;
        end
        // ...
    endcase
end
```

## 测试场景

### 测试 1: 单目运算 - 转置
```
1. enable = 1, op_code = OP_TRANSPOSE
2. 随机选择一个有效的矩阵维度
3. 读取矩阵并打印
4. 输出 sel_done = 1，计算模块接收操作数
```

### 测试 2: 双目运算 - 加法
```
1. enable = 1, op_code = OP_ADD
2. 随机选择第一个矩阵（假设 3x4）
3. 打印第一个矩阵
4. 随机选择第二个矩阵
5. 检查：如果第二个矩阵不是 3x4，则重新生成
6. 打印第二个矩阵
7. 输出 sel_done = 1
```

### 测试 3: 无有效矩阵 - 错误处理
```
1. info_table 全为 0（存储器空）
2. enable = 1, op_code = OP_ADD
3. 尝试 50 次后仍无有效矩阵
4. 进入 ERROR 状态，输出 sel_error = 1
5. 计算模块应回到 IDLE 或重新开始
```

### 测试 4: 矩阵乘法 - 维度检查
```
1. enable = 1, op_code = OP_MUL
2. 随机选择第一个矩阵 3x4
3. 随机选择第二个矩阵
4. 检查：只有当第二个矩阵为 4xN 时才接受
5. 如果不匹配，重新生成第二个矩阵
```

## 注意事项

1. **LFSR 初始值**: 默认种子为 `32'h12345678`，可根据需求修改
2. **重试上限**: MAX_RETRY = 50，可调整
3. **维度范围**: 目前支持 1-5，如需扩展可修改 MAX_DIM 常数
4. **存储仲裁**: 该模块与其他需要访问存储的模块共享读接口，需要外部仲裁逻辑
5. **打印模块**: 需要与外部矩阵打印模块有时序协调

## 可能的扩展

1. **可配置的 LFSR 种子**: 从外部输入设置随机数种子
2. **详细错误码**: 区分不同的失败原因
3. **统计信息**: 记录选择过程中的重试次数
4. **动态重试上限**: 根据矩阵数量动态调整
