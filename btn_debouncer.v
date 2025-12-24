//==============================================================================
// 按键消抖模块
//==============================================================================
//==============================================================================
// 按键消抖模块（两级同步 + 去抖计数 + 上升沿脉冲输出）
// 输出：btn_out 为消抖后的电平，pulse 为上升沿单周期脉冲
//==============================================================================
module btn_debouncer (
  input wire clk,
  input wire rst_n,
  input wire btn_in,
  output reg btn_out,
  output wire pulse
);

parameter DEBOUNCE_TIME = 20'd1000000; // 默认 20ms @50MHz

reg [19:0] counter;
reg sync0, sync1, prev_sync;
reg btn_out_d;      // 上一周期的 btn_out，用于比较
reg pulse_reg;

always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    sync0 <= 1'b0;
    sync1 <= 1'b0;
    prev_sync <= 1'b0;
    counter <= 20'd0;
    btn_out <= 1'b0;
    btn_out_d <= 1'b0;
    pulse_reg <= 1'b0;
  end else begin
    // 两级同步，降低亚稳风险
    sync0 <= btn_in;
    sync1 <= sync0;

    // 去抖计数逻辑：当同步后的输入与之前采样不同，重置计数
    if (sync1 != prev_sync) begin
      counter <= 20'd0;
      pulse_reg <= 1'b0; // 清脉冲
    end else if (counter < DEBOUNCE_TIME) begin
      counter <= counter + 1'b1;
      pulse_reg <= 1'b0;
    end else begin
      // 当计数到达阈值且稳定时，更新输出（仅在值发生变化时更新）
      if (btn_out != sync1) begin
        // 利用旧的 btn_out 与 sync1 判断是否上升沿
        btn_out <= sync1;
        // 产生上升沿脉冲，当 sync1 == 1 且 之前 btn_out == 0
        pulse_reg <= (sync1 == 1'b1) && (btn_out == 1'b0);
      end else begin
        pulse_reg <= 1'b0;
      end
    end

    // 保存用于比较的同步历史值
    prev_sync <= sync1;
    // btn_out_d 保留上一周期 btn_out（如果外部需要也可用），这里用于保证 btn_out 的边沿检测
    btn_out_d <= btn_out;
  end
end

assign pulse = pulse_reg;

endmodule