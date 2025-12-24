# UART Parser 修复说明

## 问题分析

### 从顶层到底层的数据流

```
用户输入 (串口)
    ↓
uart_rx (接收字节)
    ├─ uart_rx_done (接收完成脉冲)
    └─ uart_rx_data (接收到的字节)
        ↓
uart_parser (解析模块) ← data_input_mode_en
    ├─ 解析格式: "m n a11 a12 ... amn"
    ├─ 状态机: IDLE → PARSE_M → PARSE_N → PARSE_DATA → DONE
    └─ 输出:
        ├─ parsed_m, parsed_n (矩阵维度)
        ├─ parsed_matrix_flat (矩阵数据)
        ├─ parse_done (完成信号) ← 关键触发信号
        └─ parse_error (错误信号)
            ↓
存储和打印 (并行触发)
    ├─ 路径1: matrix_storage (存储)
    │   └─ store_write_en ← parse_done触发
    │
    └─ 路径2: matrix_printer (打印回显)
        └─ start ← parse_done触发
            ↓
        UART TX (输出到串口)
```

## 发现的问题

### 1. **超时时间设置不合理**
**问题**: 
- 原设置：GAP_TIMEOUT = 0.5秒
- 对于手动输入矩阵数据，0.5秒间隔太短

**修复**:
```verilog
// 修改前
localparam [31:0] IDLE_TIMEOUT_CYCLES = CLK_FREQ_HZ * 5;   // 5秒
localparam [31:0] GAP_TIMEOUT_CYCLES  = CLK_FREQ_HZ / 2;   // 0.5秒

// 修改后
localparam [31:0] IDLE_TIMEOUT_CYCLES = CLK_FREQ_HZ * 10;  // 10秒
localparam [31:0] GAP_TIMEOUT_CYCLES  = CLK_FREQ_HZ * 2;   // 2秒
```

### 2. **数字范围检查逻辑错误**
**问题**: 
```verilog
// 原代码 - 错误逻辑
if (current_num * 10 + (rx_data - "0") > 9) begin
    parse_error <= 1'b1;
```
这个检查意图是限制元素为0-9，但逻辑有误：
- 无法处理elem_min/elem_max参数
- 检查条件不准确

**修复**:
```verilog
// 新代码 - 正确逻辑
if (num_started) begin
    // 已经开始输入数字，检查新值是否在范围内
    if (current_num * 10 + (rx_data - "0") <= elem_max) begin
        current_num <= current_num * 10 + (rx_data - "0");
    end else begin
        // 超出范围，报错
        parse_error <= 1'b1;
        state <= ERROR;
    end
end else begin
    // 第一个数字
    current_num <= rx_data - "0";
    num_started <= 1'b1;
end
```

### 3. **空格判断不一致**
**问题**: 代码中混用了`" "`和`8'h20`表示空格

**修复**: 统一使用`8'h20`

### 4. **空格处理逻辑重复和冲突**
**问题**: 
```verilog
// PARSE_DATA状态中
else if ((rx_data == " " || ...) && num_started) begin
    // 处理分隔符
end else if (rx_data == 8'h20) begin
    // 忽略空格 - 这行永远不会执行！
end
```

**修复**: 合并空格处理逻辑
```verilog
else if ((rx_data == 8'h20 || rx_data == 8'h0D || rx_data == 8'h0A) && num_started) begin
    // 完成一个元素
    ...
end else if (rx_data == 8'h20 || rx_data == 8'h0D || rx_data == 8'h0A) begin
    // 忽略多余的空格、回车、换行
end
```

### 5. **状态转换时标志未清除**
**问题**: 从ERROR或DONE返回IDLE时，`parse_done`和`parse_error`没有清除

**影响**: 
- 导致重复触发存储和打印
- 下一次解析可能受影响

**修复**: 在IDLE状态进入PARSE_M时清除标志
```verilog
IDLE: begin
    if (parse_enable) begin
        state <= PARSE_M;
        // ... 其他初始化
        parse_done <= 1'b0;  // 清除完成标志
        parse_error <= 1'b0; // 清除错误标志
        parsed_m <= 3'd0;    // 清除上次的结果
        parsed_n <= 3'd0;
    end
end
```

### 6. **前导空格和换行处理**
**问题**: PARSE_M和PARSE_N状态没有处理前导空格

**修复**: 添加空格和换行的忽略逻辑
```verilog
end else if (rx_data == 8'h20 || rx_data == 8'h0D || rx_data == 8'h0A) begin
    // 忽略前导空格和换行
end
```

## 修复后的状态机逻辑

### PARSE_M (解析行数)
```
接收数字 → 累加到current_num
接收空格 + num_started → 验证范围 → 保存parsed_m → 转PARSE_N
接收空格/回车/换行 (无num_started) → 忽略
其他字符 → ERROR
超时 → ERROR
```

### PARSE_N (解析列数)
```
接收数字 → 累加到current_num
接收空格 + num_started → 验证范围 → 保存parsed_n → 转PARSE_DATA
接收空格/回车/换行 (无num_started) → 忽略
其他字符 → ERROR
超时 → ERROR
```

### PARSE_DATA (解析矩阵元素)
```
接收数字 → 检查范围 → 累加到current_num
接收分隔符 + num_started → 保存元素 → elem_index++
    ├─ 如果elem_index达到m*n → DONE
    └─ 否则继续接收
接收分隔符 (无num_started) → 忽略
超时 → 保存当前数字(如果有) → DONE
元素已满 → DONE
其他字符 → ERROR
```

## 测试建议

### 测试用例1: 正常输入
```
输入: "2 3 1 2 3 4 5 6"
期望: 
- parsed_m = 2, parsed_n = 3
- matrix = [1,2,3,4,5,6]
- parse_done = 1
```

### 测试用例2: 前导空格
```
输入: "  2  3  1 2 3 4 5 6  "
期望: 同上
```

### 测试用例3: 元素不足
```
输入: "2 3 1 2 3"
等待2秒超时
期望:
- parsed_m = 2, parsed_n = 3
- matrix = [1,2,3,0,0,0] (自动补0)
- parse_done = 1
```

### 测试用例4: 元素超出
```
输入: "2 2 1 2 3 4 5 6 7 8"
期望:
- parsed_m = 2, parsed_n = 2
- matrix = [1,2,3,4] (忽略后续)
- parse_done = 1
```

### 测试用例5: 范围错误
```
输入: "2 2 1 15 3 4"
期望:
- parse_error = 1 (15超出0-9范围)
```

### 测试用例6: 维度错误
```
输入: "6 3 ..." 或 "2 0 ..."
期望:
- parse_error = 1 (m,n必须在1-5范围内)
```

## 打印逻辑验证

### 触发条件
```verilog
matrix_printer u_print_for_parse (
    .start(parse_done),  // 由parse_done触发
    ...
);
```

### 时序
```
T0: 用户输入最后一个数字
T1: uart_parser检测到超时或完成
T2: parse_done = 1 (持续1个时钟周期或更长)
T3: matrix_printer检测到start信号
T4: 开始打印矩阵
    ├─ 逐字节发送到UART TX
    └─ 完成后 print_done_parse = 1
```

### 可能的问题
1. **parse_done持续时间**: 
   - 当前实现中，parse_done会保持到parse_enable=0或重新开始
   - matrix_printer需要边沿检测还是电平触发？
   - 建议检查matrix_printer的实现

2. **UART TX忙状态**:
   - matrix_printer会检查tx_busy
   - 如果UART TX正忙，打印会等待

3. **模式切换**:
   - 必须确保data_input_mode_en在整个解析和打印过程保持有效
   - 否则可能中断打印

## 调试建议

### 添加LED指示
```verilog
// 在sys_top中添加
assign led[0] = parse_enable;      // 解析使能
assign led[1] = parse_done;        // 解析完成
assign led[2] = parse_error;       // 解析错误
assign led[3] = print_done_parse;  // 打印完成
assign led[4] = uart_tx_busy;      // UART忙
```

### 添加状态监控
在uart_parser中输出当前状态：
```verilog
output reg [2:0] current_state,  // 调试用
assign current_state = state;
```

### 使用仿真
建议创建testbench验证：
1. 各种输入格式
2. 超时情况
3. 错误处理
4. parse_done信号时序

## 总结

主要修复点：
1. ✅ 增加超时时间 (0.5s → 2s)
2. ✅ 修正数字范围检查逻辑
3. ✅ 统一空格表示方法
4. ✅ 清除状态转换时的标志
5. ✅ 处理前导空格和换行
6. ✅ 移除重复的空格处理逻辑

这些修改应该能解决无法正确输入和打印的问题。
