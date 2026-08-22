`timescale 1ns / 1ps

module uart(
    reset, txclk, ld_tx_data, tx_data, tx_enable, tx_out, tx_empty,
    rxclk, uld_rx_data, rx_data, rx_enable, rx_in, rx_empty
);

// Port declarations
input reset;
input txclk;
input ld_tx_data;
input [7:0] tx_data;
input tx_enable;
output tx_out;
output tx_empty;
input rxclk;
input uld_rx_data;
output [7:0] rx_data;
input rx_enable;
input rx_in;
output rx_empty;

// Internal Variables
reg [7:0] tx_reg;
reg tx_empty;
reg tx_over_run;
reg [3:0] tx_cnt;
reg tx_out;

reg [7:0] rx_reg;
reg [7:0] rx_data;
reg [3:0] rx_sample_cnt;
reg [3:0] rx_cnt;
reg rx_frame_err;
reg rx_over_run;
reg rx_empty;
reg rx_d1;
reg rx_d2;
reg rx_busy;

//====================================================
// UART RX Logic
// 8x-oversampling receiver: rxclk must run 8x faster
// than txclk (see testbench clock divider).
//====================================================
always @(posedge rxclk or posedge reset)
begin
    if (reset)
    begin
        rx_reg         <= 8'd0;
        rx_data        <= 8'd0;
        rx_sample_cnt  <= 4'd0;
        rx_cnt         <= 4'd0;
        rx_frame_err   <= 1'b0;
        rx_over_run    <= 1'b0;
        rx_empty       <= 1'b1;
        rx_d1          <= 1'b1;
        rx_d2          <= 1'b1;
        rx_busy        <= 1'b0;
    end
    else
    begin
        // Synchronize asynchronous input
        rx_d1 <= rx_in;
        rx_d2 <= rx_d1;

        // Unload RX data
        if (uld_rx_data)
        begin
            rx_data  <= rx_reg;
            rx_empty <= 1'b1;
        end

        if (rx_enable)
        begin
            // Detect start bit
            if (!rx_busy && !rx_d2)
            begin
                rx_busy       <= 1'b1;
                rx_sample_cnt <= 4'd1;
                rx_cnt        <= 4'd0;
            end

            if (rx_busy)
            begin
                rx_sample_cnt <= rx_sample_cnt + 1'b1;

                // Sample in the middle of the bit window
                if (rx_sample_cnt == 4'd7)
                begin
                    rx_cnt <= rx_cnt + 1'b1;

                    if ((rx_d2 == 1'b1) && (rx_cnt == 4'd0))
                        rx_busy <= 1'b0;
                    else
                    begin
                        if (rx_cnt > 0 && rx_cnt < 9)
                            rx_reg[rx_cnt-1] <= rx_d2;

                        if (rx_cnt == 4'd9)
                        begin
                            rx_busy <= 1'b0;
                            if (!rx_d2)
                                rx_frame_err <= 1'b1;
                            else
                            begin
                                rx_empty     <= 1'b0;
                                rx_frame_err <= 1'b0;
                            end
                            rx_over_run <= (rx_empty) ? 1'b0 : 1'b1;
                        end
                    end
                    rx_sample_cnt <= 4'd0;
                end
            end
        end

        if (!rx_enable)
            rx_busy <= 1'b0;
    end
end

//====================================================
// UART TX Logic
//====================================================
always @(posedge txclk or posedge reset)
begin
    if (reset) begin
        tx_reg      <= 8'd0;
        tx_empty    <= 1'b1;
        tx_over_run <= 1'b0;
        tx_out      <= 1'b1;
        tx_cnt      <= 4'd0;
    end else begin
        if (ld_tx_data)
        begin
            if (!tx_empty)
                tx_over_run <= 1'b1;
            else
            begin
                tx_reg   <= tx_data;
                tx_empty <= 1'b0;
            end
        end

        if (tx_enable && !tx_empty)
        begin
            tx_cnt <= tx_cnt + 1'b1;
            if (tx_cnt == 0)
                tx_out <= 1'b0; // Start bit
            if (tx_cnt > 0 && tx_cnt < 9)
                tx_out <= tx_reg[tx_cnt-1];
            if (tx_cnt == 9)
            begin
                tx_out   <= 1'b1; // Stop bit
                tx_cnt   <= 4'd0;
                tx_empty <= 1'b1;
            end
        end

        if (!tx_enable)
            tx_cnt <= 4'd0;
    end
end

endmodule
