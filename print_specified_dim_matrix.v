module print_specified_dim_matrix(
    input wire clk,
    input wire rst_n,
    input wire start,
    input
    // UART TX 接口
    input wire uart_tx_busy,
    output reg uart_tx_en,
    output reg [7:0] uart_tx_data,
    input wire [49:0] info_table,
    input wire [2:0] dim_m, // 指定打印的维度（1-5）
    input wire [2:0] dim_n, // 指定打印的维度（1-5）
    //UART RX接口
    output 


    
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


module uart_tx(
    input               clk         , //系统时钟
    input               rst_n       , //系统复位，低有效
    input               uart_tx_en  , //UART的发送使能
    input     [7:0]     uart_tx_data, //UART要发送的数据
    output  reg         uart_txd    , //UART发送端口
    output  reg         uart_tx_busy  //发送忙状态信号
    );