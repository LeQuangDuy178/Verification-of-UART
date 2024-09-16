//-----------------------------UART.sv----------------------//
// Digital RTL Design of UART

`timescale 1ns/1ps

/////////////////////////////////////
// Interface for DUT UART
interface uart_inf;

    // System clk, UART clk for TX, RX
    logic clk;
    logic uclk_tx;
    logic uclk_rx;

    logic rst;
    
    // For RX
    logic rx; // Rxd Receiver port of UART
    logic [7:0] dout_rx;
    logic done_rx;

    // For TX
    logic tx; // Txd Transmitter port of UART
    logic [7:0] din_tx; // 8-bit transmitter data of data in
    logic new_data; // Flag for new data transfer
    logic done_tx;

endinterface

////////////////////////////////////////////////////////
// UART Top-module
module UART
#(parameter clk_freq = 1000000, parameter baud_rate = 9600)
(clk, rst, tx, din_tx, new_data, done_tx, rx, dout_rx, done_rx);

    // System signal
    input clk;
    input rst;

    // RX
    input logic rx;
    output logic [7:0] dout_rx;
    output logic done_rx;

    // TX
    input logic new_data;
    input logic [7:0] din_tx;
    output logic tx;
    output logic done_tx;


    // Instatiation 2 sub-module
    // TX
    uart_tx #(clk_freq, baud_rate) utx_ins(
        .clk(clk),
        .rst(rst),
        .newd(new_data),
        .tx_data(din_tx), // .register(input)
        .tx(tx),
        .donetx(done_tx)
    );

    //RX
    uart_rx #(clk_freq, baud_rate) urx_ins(
        .clk(clk),
        .rst(rst),
        .rx(rx),
        .donerx(done_rx),
        .rx_data(dout_rx) // .register(output)
    );



endmodule



////////////////////////////////////////////////////////
// Sub-module for UART digital design

// UART Transmitter
module uart_tx // #() static data
#( parameter clk_freq = 1000000, // Clock frequency
   parameter baud_rate = 9600) // baud rate transferring
(clk, rst, newd, tx_data, tx, donetx);

    input clk;
    input rst;
    input newd; // New data flag 
    input [7:0] tx_data; // 8-bit tx
    output logic tx; // Single bit tx data
    output logic donetx; // Flag checking tx done state

    // Clkfreq / baudcalc = 1 clk cycle 
    localparam clkcount = (clk_freq/baud_rate); 

    // integer type 32-bit
    integer count = 0;  // count of system clock
    integer counts = 0; // count of system UART clock

    // State of TX operation
    enum bit [1:0] {idle = 2'b00, start = 2'b01, transfer = 2'b10, done = 2'b11} state;

    ////////////
    // UART clk generator
    logic uclk = 0; // clock of UART (slower clk - bit duration)
    always @(posedge clk)
    begin
        if (count < clkcount/2) // Half clk period
            count <= count + 1;
        else begin
            count <= 0;
            uclk <= ~uclk; // UART clk cycle
        end
    end

    ////////////////////////////////
    // Trigger operation with sensitive uclk
    logic [7:0] din; // Data transfer within TXD of UART
    always @(posedge uclk)
    begin
        if(rst)
        begin
            state <= idle; // Reset to IDLE mode
        end
        else
        begin
            case(state) // 4 cases of state

                // First case IDLE
                idle: begin
                    counts <= 0;
                    tx <= 1'b1; // Initiate tx transfer
                    donetx <= 1'b0;
                    
                    if (newd) // Ready transfering
                    begin
                        state <= transfer;
                        tx <= 1'b0; // Ready to get new data
                        din <= tx_data;
                    end 
                    else
                        state <= idle; // Remain IDLE
                end

                // Second case Transfer
                transfer: begin
                    if (counts <= 7) // Transfer 7 time
                    begin
                        counts <= counts + 1; // counts++
                        tx <= din[counts]; // Transfer single bit data once
                        state <= transfer;
                    end
                    else
                    begin
                        counts <= 0;
                        tx <= 1'b1;
                        state <= idle;
                        donetx <= 1'b1;
                    end
                end

                // Default case
                default: state <= idle;
            endcase
        end
    end

endmodule


///////////////////////////////////////////////////////////



// UART Receiver
module uart_rx // #() static data
#( parameter clk_freq = 1000000, // Clock frequency MHz
   parameter baud_rate = 9600) // baud rate transferring
(clk, rst, rx, donerx, rx_data);

    input clk;
    input rst;
    input rx; // Single bit data rx
    output logic [7:0] rx_data; // 8-bit rx data
    output logic donerx; 

    localparam clkcount = (clk_freq/baud_rate); // Rate for 1 clk cycle

    integer count = 0; // Count for system clk
    integer counts = 0; // Count for system UART clk

    enum bit [1:0] {idle = 2'b00, start = 2'b01} state; 

    // UART clk generation
    logic uclk = 0;
    always @(posedge clk)
    begin
        if (count < clkcount/2) // Count < half clkcount UART
            count <= count + 1;
        else
        begin
            count <= 0;
            uclk <= ~uclk;
        end
    end

    ////////////////////////////////////////////////
    // UART clk operation
    always @(posedge uclk)
    begin
        if (rst)
        begin
            rx_data <= 8'b00;
            counts <= 0;
            donerx <= 1'b0;
        end
        else
        begin
            case(state)

                // First case IDLE
                idle: begin
                    rx_data <= 8'b00;
                    counts <= 0;
                    donerx <= 1'b0;

                    if (rx == 1'b0) // if (!rx)
                        state <= start;
                    else
                        state <= idle;
                end

                // Second case Start
                start: begin
                    if (counts <= 7)
                    begin
                        counts <= counts + 1;
                        rx_data <= {rx, rxdata[7:1]}; // {MSB,LSB}
                    end
                    else
                    begin
                        counts <= 0; // Finish receive all data
                        donerx <= 1'b1;
                        state <= idle;
                    end
                end

                default: state <= idle;
            endcase
        end
    end

endmodule