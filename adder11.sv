//TRANSACTION
class transaction;
  randc bit[3:0] a;  //only input must be randomized
  randc bit[3:0] b;
  bit[6:0] c;
  
  function void display(string name);
    $display("----------------------------------");
    $display(" %s", name);
    //$display("----------------------------------");
    $display("a = %0d  b = %0d  c = %0d", a, b, c);
  endfunction

  function int randomize_transaction();
    a = $urandom_range(5,15); // Randomize addr1
    b = $urandom_range(5,15); // Randomize addr2 with a constraint
    c = a + b; // Set c as the sum of a and b
    return 1;
  endfunction
endclass

//GENERATOR
class generator;
  int pkt_count;     //to count num of packets
  transaction trans;
  mailbox gen2drv;   //create a handle of mailbox to send and recieve pkts
  event pktGenEnded; //create an event to dictate the end of the event
  
  //constructor
  function new(mailbox gen2drv);
    this.gen2drv = gen2drv;
  endfunction

  task main();
    repeat(pkt_count) begin
      trans = new();
      if (!trans.randomize_transaction()) // Call the custom randomize function
        $fatal("Gen:: trans randomization failed");
      
      trans.display("[ Generator ]");
      gen2drv.put(trans); 
    end
    -> pktGenEnded;
  endtask
endclass

//INTERFACE
interface intf(input clk, reset);
  logic valid;
  logic [3:0] a;
  logic [3:0] b;
  logic [6:0] c;
endinterface

//DRIVER
class driver;
  mailbox gen2drv;
  virtual intf vif;
  int num_transactions = 0;

  function new(virtual intf vif, mailbox gen2drv);
    this.vif = vif;
    this.gen2drv = gen2drv;
  endfunction

  task reset;
    wait(vif.reset);
    $display("[DRIVER]----RESET STARTED----");
    vif.a <= 0;
    vif.b <= 0;
    vif.valid <= 0;
    wait(!vif.reset);
    $display("[DRIVER]----RESET ENDED----");
  endtask

  task main;
    forever begin
      transaction trans;
      gen2drv.get(trans);
      @(posedge vif.clk);
      
      vif.valid <= 1;
      vif.a <= trans.a;
      vif.b <= trans.b;
      @(posedge vif.clk);
      
      vif.valid <= 0;
      trans.c = vif.c;
      @(posedge vif.clk);
      
      trans.display("DRIVER");
      num_transactions++;
    end
  endtask
endclass

//MONITOR
class monitor;
  virtual intf vif;
  mailbox mon2scb;

  function new(virtual intf vif, mailbox mon2scb);
    this.vif = vif;
    this.mon2scb = mon2scb;
  endfunction

  task main;
    forever begin
      transaction trans;
      wait(vif.valid);
      @(posedge vif.clk);
      
      trans = new();
      trans.a = vif.a;
      trans.b = vif.b;
      @(posedge vif.clk);
      
      trans.c = vif.c;
      //@(posedge vif.clk);
      
      mon2scb.put(trans);
      trans.display("[ Monitor ]");
    end
  endtask
endclass

//SCOREBOARD
class scoreboard;
  mailbox mon2scb;
  int num_transactions = 0;

  function new(mailbox mon2scb);
    this.mon2scb = mon2scb;
  endfunction

  task main;
    transaction trans;
    forever begin
      mon2scb.get(trans);
      if ((trans.a + trans.b) == trans.c)
        $display("Result is as Expected"); 
      else
        $display("Wrong Result. Expected: %0d Actual: %0d", (trans.a+trans.b), trans.c); 

      num_transactions++;
      trans.display("[ Scoreboard ]");
    end
  endtask
endclass

//ENVIRONMENT
class environment;
  generator gen;
  driver drv;
  monitor mon;
  scoreboard scb;
  mailbox gen2drv;
  mailbox mon2scb;
  virtual intf vif;

  function new(virtual intf vif);
    this.vif = vif;
    gen2drv = new();
    mon2scb = new();
    gen = new(gen2drv);
    drv = new(vif, gen2drv);
    mon = new(vif, mon2scb);
    scb = new(mon2scb);
  endfunction

  task pre_test;
    drv.reset();
  endtask

  task test;
    fork 
      gen.main();
      drv.main();
      mon.main();
      scb.main();
    join_any
  endtask

  task post_test;
    wait(gen.pktGenEnded.triggered);
    wait(gen.pkt_count == scb.num_transactions);
  endtask  

  task run;
    pre_test();
    test();
    post_test();
    $finish;
  endtask
endclass

//TEST
module test(intf intf);
  environment env;
  initial begin
    env = new(intf);
    env.gen.pkt_count = 3;
    env.run();
  end
endmodule

//TOP
module tb_topModule;
  bit clk;
  bit reset;

  always #5 clk = ~clk;
  initial begin
    reset = 1;
    #3 reset = 0;
  end

  intf i_intf(clk, reset);
  test t1(i_intf);
endmodule

