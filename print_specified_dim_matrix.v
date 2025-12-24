module print_specified_dim_matrix(
    input wire clk,
    input wire rst_n,
    input wire start,
    //UART RX 接口
    input wire uart_rx_done,
    input wire [7:0] uart_rx_data,
    // UART TX 接口
    input wire uart_tx_busy,
    output reg uart_tx_en,
    output reg [7:0] uart_tx_data,
    input wire [49:0] info_table,
    input wire [2:0] specified_dim, // 指定打印的维度（1-5）
    
    output reg busy,
    output reg done
);
    

endmodule

module uart_rx(
    input               clk         ,  //系统时钟
    input               rst_n       ,  //系统复位，低有效

    input               uart_rxd    ,  //UART接收端口
    output  reg         uart_rx_done,  //UART接收完成信号
    output  reg  [7:0]  uart_rx_data   //UART接收到的数据
    );