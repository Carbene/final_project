set_property PACKAGE_PIN P17   [get_ports clk]        
set_property IOSTANDARD LVCMOS33 [get_ports clk]

set_property PACKAGE_PIN P15  [get_ports rst_n]      
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

set_property PACKAGE_PIN R1   [get_ports enable]      
set_property IOSTANDARD LVCMOS33 [get_ports enable]

set_property PACKAGE_PIN N5   [get_ports uart_rxd]   
set_property IOSTANDARD LVCMOS33 [get_ports uart_rxd]

set_property PACKAGE_PIN T4   [get_ports uart_txd]    
set_property IOSTANDARD LVCMOS33 [get_ports uart_txd]

# 调试 LED（8位）
set_property PACKAGE_PIN K2  [get_ports dbg_led[0]]
set_property PACKAGE_PIN J2   [get_ports dbg_led[1]]
set_property PACKAGE_PIN J3   [get_ports dbg_led[2]]
set_property PACKAGE_PIN H4   [get_ports dbg_led[3]]
set_property PACKAGE_PIN J4   [get_ports dbg_led[4]]
set_property PACKAGE_PIN G3   [get_ports dbg_led[5]]
set_property PACKAGE_PIN G4   [get_ports dbg_led[6]]
set_property PACKAGE_PIN F6   [get_ports dbg_led[7]]
set_property IOSTANDARD LVCMOS33 [get_ports dbg_led[*]]