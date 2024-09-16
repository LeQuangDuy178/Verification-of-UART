//-----------------------------UART_tb.sv---------------------//
// Digital RTL Verification of UART\

`timescale 1ns/1ps


////////////////////////////////////////////////
// Data transaction class
class transaction;

    typedef enum bit {write = 1'b0, read 1'b1} operation_type; // %0s scanf

    randc operation_type oper; // Should not replicate

    bit rx;
    bit [7:0] dout_rx;
    bit done_rx;

    bit tx;
    bit done_tx;
    rand bit [7:0] din_tx; // Random data sent into tx pin
    bit new_data;

    // Deep copy
    function transaction copy();
        copy = new();
        copy.rx = this.rx;
        copy.oper = this.oper;
        copy.dout_rx = this.dout_rx;
        copy.done_rx = this.done_rx;
        copy.tx = this.tx;
        copy.done_tx = this.done_tx;
        copy.din_tx = this.din_tx;
        copy.new_data = this.new_data
    endfunction

    // // Display
    // task transaction display(tag, din_tx, dout_rx);
    //     $display("[%0s] : DATA TX : %0b : DATA RX : %0b", tag, din_tx, dout_rx);
    // endtask

endclass


// GEN: generator; DRV: driver; MON: monitor; SCO: scoreboard
////////////////////////////////////////////////
// Classes in verification environment
// If data mismatched then considered clk tick issues

// Class generator
class generator;

    transactrion trans;

    mailbox #(transaction) mbx; // Send from GEN to DRV

    event done; // Trigger when all stimulies complete

    int count = 0; // The number of stimulies (user-referenced)

    event drvnext; // Wait for driver confirm next stimuli
    event sconext; // Wait for scoreboard confirm finish

    function new(mailbox #(transaction) mbx);
        this.mbx = mbx; // Mailbox synchronize
        trans = new(); // New object every stimuli
    endfunction

    task main(); // Main task of scoreboard

        repeat(count) // Repeat operation within number of stimulies
        begin
            assert(trans.randomize) else $display("Randomization failed");
            mbx.put(trans.copy); // Put deep copy of trans to send to DRV
            $display("[GEN] : Operation : %0s : Din : %0d", trans.oper.name(), trans.din_tx);
            @(drvnext); // Wait for drvnext event
            @(sconext); // Wait for sconext event
        end

        -> done; // Trigger done event when all stimulies are applied

    endtask

endclass

/////////////////////////////////////////////////////////////////////////////
// Class driver
class driver;

    virtual uart_inf uart; // Interface object store data to send to DUT

    transaction trans;

    event drvnext; // Trigger drvnext to implement next stimuli from generator

    bit [7:0] din;
    bit write = 0; // urandom write/read operation
    bit [7:0] data_rx; // Output of driver to send to DUT - array form

    mailbox #(transaction) mbx_dtm; // Driver to monitor through DUT
    mailbox #(bit [7:0]) mbx_dts; // Driver to scoreboard for referenced data to compare

    function new(mailbox #(transaction) mbx_dtm, mailbox #(bit [7:0]) mbx_dts)
        this.mbx_dtm = mbx_dtm;
        this.mbx_dts = mbx_dts;
    endfunction

    task reset();
        uart.rst <= 1'b1;
        uart.din_tx <= 0;
        uart.new_data <= 0;
        uart.rx <= 1'b1;

        repeat (5) @(posedge uart.uclk_tx) // Wait for 5 UART TX clk tick to disable rst
        uart.rst <= 1'b0;
        @(posedge uart.uclk_tx) // wait for one more
        $display("[DRV]: RESET COMPLETED");
        $display("-------------------------------------------------------");
    endtask

    task main();

        forever // Everytime mailbox of trans data received from generator 
        begin
            mbx.get(trans);

            // Configure data get from DIN of GEN for virtual interface then send to DUT ports
            if (trans.oper == 1'b0) // Write data (transmitting data)
            begin
                @(posedge uart.uclk_tx) // sensitive for uart transmitting pin clk
                uart.rst <= 1'b0;
                uart.new_data <= 1'b1; // Start get new data
                uart.rx <= 1'b1; // Ready to read data
                uart.din_tx <= trans.din_tx; // Assign rand value of din_tx to uart interface
                
                @(posedge uart.uclk_tx);
                uart.new_data <= 1'b0;
                mbx_dts.put(trans.din_tx); // Send trans from DRV to SCO for ref
                $display("[DRV]: DATA SENT : %0d", trans.din_tx);
                wait(uart.done_tx); // Wait for done_tx event from SCO trigger
                -> drvnext; // Trigger drvnext from DRV to GEN wait
            end

            else if (trans.oper == 1'b1) // Read data (receiving data)
            begin
                @(posedge uart.uclk_rx)
                uart.rst <= 1'b0;
                uart.rx <= 1'b0;
                uart.new_data <= 1'b0;
                @(posedge uart.uclk_rx) // Wait for next clk tick 
            
                for (int i = 0; i <= 7; i++)
                begin
                    @(posedge uart.uclk_rx); // Wait for 1 clk tick for system to gain next data
                    uart.rx <= $urandom; // Create rand 8-bits data
                    data_rx[i] = uart.rx; // Then read singly data to data_rx array
                end

                mbx_dts.put(data_rx); // Send data_rx readed to scoreboard as well

                $display("[DRV] : DATA RECEIVED : %0d", data_rx);
                wait(uart.done_rx);
                uart.rx <= 1'b1;
                -> drvnext;
            end
        end

    endtask

endclass


//////////////////////////////////////////////////////////////////////////////////
// Class monitor
class monitor;

    transaction trans;

    bit [7:0] s_rx; // Sending data to scoreboard
    bit [7:0] r_rx; // Receiving data from driver

    virtual uart_inf uart; // Interface to gather data from DUT

    mailbox #(bit [7:0]) mbx; // Received from driver (the 8-bit data)

    function new(mailbox #(bit [7:0]) mbx)
        this.mbx = mbx;
    endfunction

    task main();

        forever
        begin
            
            @(posedge uart.uclk_tx) // UART clock of TX
            if ((uart.new_data == 1'b1) && (uart.rx == 1'b1)) // If new_data and rx enable
            begin
                @(posedge uart.uclk_tx); // Start collecting tx data in next clk tick
                for (int i = 0; i <= 7; i++)
                begin
                    @(posedge uart.uclk_tx)
                    s_rx[i] = uart.tx;
                end

                $display("[MON]: DATA SEND ON UART TX : %0d", s_rx);
                // Wait for done_tx for the next transaction
                @(posedge uart.uclk_tx);
                mbx.put(s_rx); // Send to scoreboard
            end

            else if ((uart.new_data == 1'b0) && (uart.rx == 1'b0)) 
            begin
                wait(uart.done_rx); // Wait done_rx confirm completed
                r_rx = uart.dout_rx; // Assign received data of rx to DUT
                $display("[MON] : DATA RECEIVED FROM RX : %0d", r_rx);
                @(posedge uart.uclk_tx); // Wait next clk tick to send data to scoreboard
                mbx.put(r_rx);
            end

        end

    endtask

endclass


//////////////////////////////////////////////////////////////////////////////////
// Class scoreboard
class scoreboard;

    mailbox #(bit [7:0]) mbx_dts; // Driver to scoreboard
    mailbox #(bit [7:0]) mbx_mts; // Monitor to scoreboard

    bit [7:0] dts; // DRV to SCO data
    bit [7:0] mts; // MON to SCO data

    event sconext; // Trigger when complete

    function new(mailbox #(bit [7:0]) mbx_dts, mailbox #(bit [7:0]) mbx_mts)
        this.mbx_dts = mbx_dts;
        this.mbx_mts = mbx_mts;
    endfunction

    task main()

        forever
        begin
            
            mbx_dts.get(dts);
            mbx_mts.get(mts); // Wil connect to monitor and driver later on

            $display("[SCO] : DRV : %0d : MON : %0d", dts, mts);
            if(dts = mts)
                $display("DATA MATCHED");
            else
                $display("DATA MISMATCHED");
            $display("----------------------------------------------------------")

            -> sconext;

        end

    endtask

endclass


//////////////////////////////////////////////////////////////////////////////////
// Class environment - containing all 4 modules
class environment;

    generator gen;
    driver drv;
    monitor mon;
    scoreboard sco;

    event next_gtd; // GEN -> DRV when DRV confirms
    event next_gts; // GEN -> SCo when SCO confirms

    mailbox #(transaction) mbx_gtd; // GEN -> DRV
    mailbox #(bit [7:0]) mbx_mts; // MON -> SCO
    mailbox #(bit [7:0]) mbx_dts; // DRV -> SCO

    virtual uart_inf uart;

    function new(virtual uart_inf uart) // Connect designed DUT to environment DUT
        mbx_gtd = new();
        mbx_mts = new();
        mbx_dts = new();

        gen = new(mbx_gtd);
        drv = new(mbx_dts, mbx_gtd); // dts used to send as ref to dtm, gtd to send as dts
        mon = new(mbx_mts);
        sco = new(mbx_dts, mbx_mts);
        
        this.uart = uart;
        this.uart = drv.uart; // Driver interface connected to DUT interface
        this.uart = mon.uart; // Same for monitor

        gen.sconext = next_gts;
        sco.sconext = next_gts; // Connect event of GEN to SCO

        gen.drvnext = next_gtd;
        drv.drvnext = next_gtd; // Connect event of GEN to DRV
        
    endfunction

    task pre_test();
        drv.reset();
    endtask

    task test();
        fork
            gen.main();
            drv.main();
            mon.main();
            sco.main();
        join_any
    endtask

    task post_test();
        wait(gen.done.triggered) // Wait for all stimulies in generator completed
        $finish(); // To finish the program
    endtask

    task run(); // Run all 3 stages of test
        pre_test();
        test();
        post_test(); // No fork_join because the tasks run respectively
    endtask


endclass


//////////////////////////////////////////////////////////////////////////
// Top-level module with all modules
module UART_tb;

    uart_inf uart();

    // Module instantiation (With data parameter for clk freq and baud rate)
    UART #(1000000, 9600) uart_ins 
    (
        .clk(uart.clk),
        .rst(uart.rst),
        .tx(uart.tx),
        .din_tx(uart.din_tx),
        .done_tx(uart.done_tx),
        .new_data(uart.new_data),
        .rx(uart.tx),
        .dout_rx(uart.dout_rx),
        .done_rx(uart.done_rx),
    );

    // Clk signal generator
    initial begin
        uart.clk <= 0;
    end

    always #10 uart.clk <= ~uart.clk; // 10ns = half period clk

    environment env;

    initial begin
        env = new(uart);
        env.gen.count = 17; // 17 stimulies
        env.run();
    end

    initial begin
        $dumpfiles("dump.vcd");
        $dumpvars;
    end

    // Assign uclk of interface to DUT sub-module TX/RX uclk
    assign uart.uclk_tx = uart_ins.uart_tx.uclk;
    assign uart.uclk_rx = uart_ins.uart_rx.uclk; 

endmodule