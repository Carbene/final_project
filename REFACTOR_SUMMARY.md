# 卷积引擎周期数发送模块重构总结

## 问题分析
之前的设计问题：
1. **UART接口不匹配**：`convolution_engine.v` 中使用了不存在的 `uart_tx_ready` 信号
2. **系统使用脉冲控制**：`sys_top.v` 中的 `uart_tx` 模块使用 `uart_tx_en`（脉冲），而非持续的 `uart_tx_valid` 信号
3. **状态机卡死**：导致LED3、4持续亮起（busy信号卡住），串口助手闪退（数据发送异常）

## 解决方案
### 新建模块：`cycle_counter_tx.v`
独立的UART周期数发送模块，特点：
- **清晰的状态机**：按顺序发送 `<百十个>` 和 `\r\n` 8个字符
- **正确的握手逻辑**：
  - 在 `WAIT_READY` 状态等待 `uart_tx_busy` 为低
  - 发送脉冲后立即回到等待状态
  - 保证每个字符完全发送后再发送下一个
- **完成信号**：`done` 输出在所有字符发送完毕后拉高

### 修改文件

#### 1. `convolution_engine.v`
**移除的内容：**
- 删除了错误的 UART 发送状态机（使用 `uart_tx_ready`）
- 移除了 `uart_tx_valid` 信号

**添加的内容：**
- 实例化 `cycle_counter_tx` 模块
- 更新输出接口为 `uart_tx_en`（脉冲）
- 状态机转移条件改为 `if (cycle_tx_done)`

**关键改动：**
```verilog
// 周期计数和发送控制
wire cycle_tx_done;

cycle_counter_tx u_cycle_tx (
    .clk(clk),
    .rst_n(~rst),
    .enable(state == SEND_CYCLES),
    .cycle_count(cycle_counter),
    .uart_tx_en(uart_tx_en),
    .uart_tx_data(uart_tx_data),
    .uart_tx_busy(uart_tx_busy),
    .done(cycle_tx_done)
);
```

#### 2. `sys_top.v`
**修改的内容：**
- 更新 `convolution_engine` 实例化的接口：
  - `uart_tx_valid` → `uart_tx_en`
  - `uart_tx_ready` → `uart_tx_busy`（直接传递）
- 更新信号声明：`conv_uart_tx_valid` → `conv_uart_tx_en`
- 更新UART多路选择逻辑（第432行）

## 工作流程

```
RECEIVE_KERNEL (接收9个卷积核)
    ↓
COMPUTE (计算80个卷积结果，统计周期数)
    ↓
PRINT_RESULT (打印80个结果矩阵)
    ↓
SEND_CYCLES (由 cycle_counter_tx 发送 <cycles> 格式)
    - cycle_counter_tx 状态机：IDLE → WAIT_READY → SEND_LT → ... → SEND_LF → IDLE
    - 每次发送后等待 uart_tx_busy 恢复，再发下一个字符
    - 所有字符发送完成后 done 拉高
    ↓
DONE_STATE (conv_done 拉高，LED3、4熄灭)
```

## 硬件信号流

```
cycle_counter_tx.uart_tx_en  → sys_top.uart_tx_en → uart_tx 模块
cycle_counter_tx.uart_tx_data → sys_top.uart_tx_data → uart_tx 模块
uart_tx.uart_tx_busy → cycle_counter_tx.uart_tx_busy
```

## 验证清单
- [ ] 编译无误（cycle_counter_tx 模块被正确集成）
- [ ] 在 SEND_CYCLES 状态下，LED3、4应在周期数发送完后熄灭
- [ ] 串口助手收到格式为 `<XXXX>\r\n` 的周期数（无乱码）
- [ ] conv_done 信号正常拉高表示完成

## 性能特性
- **时延**：约8个UART字符时间（@115200波特率约 ≈ 695μs）
- **资源占用**：极小（仅额外一个8状态机 + 一些寄存器）
- **可靠性**：通过脉冲握手确保每个字符正确发送
