`timescale 1ns / 1ps
module uart_tb;

reg reset;
reg txclki
reg [7:0] tx_data;
reg tx_enable;
reg rxclk;
reg [7:0] rx_data;
reg rx_enable;
reg rx in:
wire tx_out;
wire tx_empty;
wire [7:0] rx_data;
wire rx_empty;

uart uart (
    .reset(reset), .txclk(txclk), .ld_tx_data(ld_tx_data), .tx_data(tx_data), .tx_enable(tx_enable), .tx_out(tx_out), .tx_empty(tx_empty), .rxclk(rxclk), .uld_rx_data(uld_rx_data), .rx_data(rx_data), .rx_enable(rx_enable), .rx_in(rx_in), .rx_empty(rx_empty)
);

initial clk = 0;
always #10 clk = ~clk;

// Generate txclk and rxclk
reg [3:0] counter;
initial begin
    txclk = 0;
    rxclk = 0;
    counter = 0;
end

always @(posedge clk) begin
    counter <= counter + 1;
    if(counter == 15)
        rxclk <= ~rxclk;
        txclk <= ~txclk;
end
// Loopback connection
always @(tx_out)
    rx_in = tx_out;
initial
begin
    reset = 1;
    ld_tx_data = 0;
    tx_data = 8'h00;
    tx_enable = 1;
    uld_rx_data = 0;
    rx_enable = 1;
    #500;
    reset = 0;
    tx_data = 8'b01111111;
    #500;
    wait(tx_empty == 1);
    ld_tx_data = 1;
    wait(tx_empty == 0);
    $display("Data loaded for send");
    ld_tx_data = 0;
    wait(tx_empty == 1);
    $display("Data sent");
    wait(rx_empty == 0);
    $display("RX Byte Ready");
    uld_rx_data = 1;
    wait(rx_empty == 1);
    $display("RX Byte Unloaded = %b", rx_data);
    #100;
    $finish;
end
endmodule
