`timescale 1ns / 1ps
module uart_tb;

    // DUT control/stimulus signals
    reg         reset;
    reg         txclk;
    reg         ld_tx_data;
    reg  [7:0]  tx_data;
    reg         tx_enable;

    reg         rxclk;
    reg         uld_rx_data;
    reg         rx_enable;
    reg         rx_in;

    // DUT outputs
    wire        tx_out;
    wire        tx_empty;
    wire [7:0]  rx_data;
    wire        rx_empty;

    // System clock + clock-divider counters
    reg        clk;
    reg [3:0]  tx_div_cnt;
    reg        rx_div_cnt;

    //====================================================
    // DUT instantiation
    //====================================================
    uart uut (
        .reset       (reset),
        .txclk       (txclk),
        .ld_tx_data  (ld_tx_data),
        .tx_data     (tx_data),
        .tx_enable   (tx_enable),
        .tx_out      (tx_out),
        .tx_empty    (tx_empty),
        .rxclk       (rxclk),
        .uld_rx_data (uld_rx_data),
        .rx_data     (rx_data),
        .rx_enable   (rx_enable),
        .rx_in       (rx_in),
        .rx_empty    (rx_empty)
    );

    //====================================================
    // System clock: 20 ns period (50 MHz)
    //====================================================
    initial clk = 0;
    always #10 clk = ~clk;

    //====================================================
    // txclk: clk / 32  -> baud-rate (bit) clock
    // rxclk: clk / 4   -> 8x oversampling clock
    //
    // rxclk MUST run 8x faster than txclk: the RX FSM samples
    // 8 times per bit window (rx_sample_cnt 0..7) to land on the
    // middle of each bit, while TX shifts out one new bit per
    // txclk edge. Equal rates (or the wrong ratio) will cause the
    // recovered byte to not match what was transmitted.
    //====================================================
    initial begin
        txclk      = 0;
        rxclk      = 0;
        tx_div_cnt = 0;
        rx_div_cnt = 0;
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            tx_div_cnt <= 4'd0;
            txclk      <= 1'b0;
        end
        else if (tx_div_cnt == 4'd15) begin
            tx_div_cnt <= 4'd0;
            txclk      <= ~txclk;
        end
        else begin
            tx_div_cnt <= tx_div_cnt + 1'b1;
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            rx_div_cnt <= 1'b0;
            rxclk      <= 1'b0;
        end
        else if (rx_div_cnt == 1'b1) begin
            rx_div_cnt <= 1'b0;
            rxclk      <= ~rxclk;
        end
        else begin
            rx_div_cnt <= rx_div_cnt + 1'b1;
        end
    end

    //====================================================
    // Loopback connection: tx_out -> rx_in
    //====================================================
    always @(tx_out)
        rx_in = tx_out;

    //====================================================
    // Test sequence
    //====================================================
    initial begin
        reset       = 1;
        ld_tx_data  = 0;
        tx_data     = 8'h00;
        tx_enable   = 1;
        uld_rx_data = 0;
        rx_enable   = 1;

        #500;
        reset   = 0;
        tx_data = 8'b01111111;   // 0x7F

        #500;
        wait (tx_empty == 1);
        ld_tx_data = 1;
        wait (tx_empty == 0);
        $display("Data loaded for send");
        ld_tx_data = 0;

        wait (tx_empty == 1);
        $display("Data sent");

        wait (rx_empty == 0);
        $display("RX Byte Ready");
        uld_rx_data = 1;
        wait (rx_empty == 1);
        $display("RX Byte Unloaded = %b", rx_data);

        if (rx_data == tx_data)
            $display("\n===================================\n   UART LOOPBACK TEST PASSED\n===================================");
        else
            $display("\n===================================\n   UART LOOPBACK TEST FAILED\n===================================");

        #100;
        $finish;
    end

endmodule
