/*
    * AXI4-Lite Slave Interface for ANN Accelerator
    * - Supports burst transactions for efficient data transfer
    * - Implements a simple memory-mapped interface for input/output data
    * - Integrates with the ANN core for processing
    * Note: This is a simplified example for demonstration purposes. In a production design,
    * additional features such as error handling, support for different burst types, and more robust state management would be necessary.
*/

`timescale 1ns / 1ps

package fsm_axi_pkg;
	typedef enum logic [1:0] {W_IDLE=2'b00,W_ADDR=2'b01,W_WRITE=2'b10,W_RESP=2'b11} write_state_t;	//state encoder for AXI write channels
	typedef enum logic [1:0] {R_IDLE=2'b00,R_ADDR=2'b01,R_DATA=2'b10} read_state_t;                 //state encoder for AXI read channels
	typedef enum logic [1:0] {WAIT=2'b00,PULL=2'b01,PUSH=2'b10} system_state_t;			            //state encoder for overall system operation
endpackage

module axi4_ann_sub #(
    parameter integer C_S_AXI_ID_WIDTH      = 1,    // Not using ID for simplicity, but can be extended
    parameter integer C_S_AXI_DATA_WIDTH    = 32,   // 32-bit data bus
    parameter integer C_S_AXI_ADDR_WIDTH    = 12,   // 4KB Address Space
    parameter integer LEN_DATASET = 150             // Number of samples in the dataset to process
)(  
    input  logic				                 clk,               // System clock for ANN core 400 MHz	
    input  logic                                 S_AXI_ACLK,        // AXI clock 100 MHz
    input  logic                                 S_AXI_ARESETN,     // Active low reset 

    // write address channel signals
    input  logic [C_S_AXI_ID_WIDTH-1 : 0]        S_AXI_AWID,    
    input  logic [C_S_AXI_ADDR_WIDTH-1 : 0]      S_AXI_AWADDR,  // Address of the first beat in the burst
    input  logic [7 : 0]                         S_AXI_AWLEN,   // Number of beats in burst (0-255, where 0 means 1 beat)
    input  logic [2 : 0]                         S_AXI_AWSIZE,  // Burst Size: bytes per beat
    input  logic [1 : 0]                         S_AXI_AWBURST, // Burst Type: 00=FIXED, 01=INCR, 10=WRAP
    input  logic                                 S_AXI_AWVALID, // Indicates that master is ready to send address
    output logic                                 S_AXI_AWREADY, // Indicates that slave is ready to accept address

    // write data channel signals
    input  logic [C_S_AXI_DATA_WIDTH-1 : 0]      S_AXI_WDATA,   // Data to be written
    input  logic [(C_S_AXI_DATA_WIDTH/8)-1 : 0]  S_AXI_WSTRB,   // Write strobe: indicates which bytes are valid in WDATA
    input  logic                                 S_AXI_WLAST,   // Indicates the last beat in a burst
    input  logic                                 S_AXI_WVALID,  // Indicates that master is ready to send data
    output logic                                 S_AXI_WREADY,  // Indicates that slave is ready to accept data

    // write response channel signals
    output logic [C_S_AXI_ID_WIDTH-1 : 0]        S_AXI_BID,     // Echoed ID for write response
    output logic [1 : 0]                         S_AXI_BRESP,   // 00=OKAY, 10=SLVERR
    output logic                                 S_AXI_BVALID,  // Indicates that slave has a valid write response
    input  logic                                 S_AXI_BREADY,  // Indicates that master is ready to accept write response

    // read address channel signals
    input  logic [C_S_AXI_ID_WIDTH-1 : 0]        S_AXI_ARID,    // Not using ID for simplicity, but can be extended
    input  logic [C_S_AXI_ADDR_WIDTH-1 : 0]      S_AXI_ARADDR,  // Address of the first beat in the burst
    input  logic [7 : 0]                         S_AXI_ARLEN,   // Number of beats in burst (0-255, where 0 means 1 beat)
    input  logic [2 : 0]                         S_AXI_ARSIZE,  // Burst Size: bytes per beat
    input  logic [1 : 0]                         S_AXI_ARBURST, // Burst Type: 00=FIXED, 01=INCR, 10=WRAP
    input  logic                                 S_AXI_ARVALID, // Indicates that master is ready to send address
    output logic                                 S_AXI_ARREADY, // Indicates that slave is ready to accept address

    // read data channel signals
    output logic  [C_S_AXI_ID_WIDTH-1 : 0]        S_AXI_RID,   
    output logic  [C_S_AXI_DATA_WIDTH-1 : 0]      S_AXI_RDATA, // Data being read
    output logic  [1 : 0]                         S_AXI_RRESP, // 00=OKAY, 10=SLVERR
    output logic                                  S_AXI_RLAST, // Indicates the last beat in a burst
    output logic                                  S_AXI_RVALID, // Indicates that slave is ready to send data
    input  logic                                  S_AXI_RREADY  // Indicates that master is ready to accept read data
);

    // control signals and internal registers
    logic axi_data_avail, ann_result_avail, test_signal, test_signal_read;
    logic unsigned [C_S_AXI_DATA_WIDTH-1:0] axi_data_out, ann_result_out;
    logic unsigned [7:0] num_sample_processed;

    // ANN Core Instantiation
    ann_core ANN_CORE_INST(
    	.clk_1_25G(clk),
	    .rst(!S_AXI_ARESETN),
	    .spi_valid_flag(S_AXI_ACLK && test_signal),
	    .spi_data_out(axi_data_out),
	    .ann_inference_out(ann_result_out),
	    .spi_ready_flag(ann_result_avail)
    );

    import fsm_axi_pkg::*;          // Importing state type definitions from the package
    
    // State registers for write, read, and overall system operation
    write_state_t 	current_write_state,  next_write_state;
    read_state_t  	current_read_state,   next_read_state;
    system_state_t	current_system_state, next_system_state;

    // Addressing 32-bit words (4 bytes), so depth is 4KB / 4 = 1024
    logic [C_S_AXI_DATA_WIDTH-1:0] mem [0 : (2**(C_S_AXI_ADDR_WIDTH-2))-1];
    logic [C_S_AXI_DATA_WIDTH-1:0] mem_out [0 : (2**(C_S_AXI_ADDR_WIDTH-2))-1];

    //+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    // state register for overall system operation
    always_ff @(posedge clk or negedge S_AXI_ARESETN) begin
    	if(!S_AXI_ARESETN)          current_system_state <= WAIT;
	    else		                current_system_state <= next_system_state;
    end

    // next state logic for overall system operation
    always_comb begin
	    case(current_system_state)
		    WAIT: next_system_state = (axi_data_avail) ? PULL:WAIT;
		    PULL: next_system_state = (num_sample_processed == LEN_DATASET) ? PUSH:PULL;
		    PUSH: next_system_state = (S_AXI_RLAST) ? WAIT:PUSH;
		    default: next_system_state = WAIT;
	    endcase
    end

    // output logic for overall system operation
    always_ff @(posedge clk) begin
    	case (current_system_state)
		WAIT: begin
			num_sample_processed <= '0;
			axi_data_out <= '0;
			test_signal <= 0;
			test_signal_read <= 0;
		end
		PULL: begin
			test_signal <= 1;
			axi_data_out <= mem[num_sample_processed];
			if(ann_result_avail) begin
				mem_out[num_sample_processed] <= ann_result_out;
				num_sample_processed <= num_sample_processed + 1;
			end
		end
		PUSH: begin
			test_signal_read <= 1;
		end
	endcase
    end
    //+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

    //=========================================================================================================
    // write state logic
    logic [C_S_AXI_ADDR_WIDTH-1 : 0] axi_awaddr;
    logic [7:0]                      axi_awlen_cntr; // Counts down beats
    logic                            axi_aw_active;  // Inside a transaction

    // state register for write channels
    always_ff @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
      if (!S_AXI_ARESETN)       current_write_state <= W_IDLE;
      else                      current_write_state <= next_write_state;
    end
	
    // next state logic for write channels
    always_comb begin
        case (current_write_state)
            W_IDLE: begin
                if (S_AXI_AWVALID) next_write_state = W_ADDR;
            end
            W_ADDR: begin
                if (S_AXI_AWREADY && S_AXI_WVALID) next_write_state = W_WRITE;
            end
            W_WRITE: begin
                if (S_AXI_WLAST) next_write_state = W_RESP;
            end
            W_RESP: begin
                if (S_AXI_BREADY) next_write_state = W_IDLE;
            end
            default: next_write_state = W_IDLE;
        endcase
    end

    // output logic for write channels
    always_ff @(posedge S_AXI_ACLK) begin
        case (current_write_state)
            W_IDLE: begin
                S_AXI_AWREADY   <= 1'b0;
                S_AXI_WREADY    <= 1'b0;
                S_AXI_BVALID    <= 1'b0;
                axi_aw_active   <= 1'b0;
                axi_awlen_cntr  <= 8'b0;
                S_AXI_BID       <= 0;     // Clear ID for response
                S_AXI_BRESP     <= 2'b01; // SLVERR by default
		axi_data_avail  <= 0;
            end
            W_ADDR: begin
                axi_awaddr     <= S_AXI_AWADDR;
                S_AXI_AWREADY  <= 1'b1;
                axi_aw_active  <= 1'b1;
                axi_awlen_cntr <= S_AXI_AWLEN; // Latch burst length
                S_AXI_BID      <= S_AXI_AWID;  // Latch ID for response
            end
            W_WRITE: begin
                S_AXI_AWREADY <= 1'b0;                      // Deassert AWREADY after address accepted
                if (axi_aw_active && !S_AXI_WREADY) begin
                    S_AXI_WREADY <= 1'b1;                   // Assert WREADY to accept data
                end
                
                if (axi_aw_active && S_AXI_WREADY && S_AXI_WVALID) begin
                    // Perform the write to memory
                    // Note: Address >> 2 because mem is indexed by 32-bit words, not bytes
                    if (S_AXI_WSTRB[0]) mem[axi_awaddr[C_S_AXI_ADDR_WIDTH-1:2]][7:0]   <= S_AXI_WDATA[7:0];
                    if (S_AXI_WSTRB[1]) mem[axi_awaddr[C_S_AXI_ADDR_WIDTH-1:2]][15:8]  <= S_AXI_WDATA[15:8];
                    if (S_AXI_WSTRB[2]) mem[axi_awaddr[C_S_AXI_ADDR_WIDTH-1:2]][23:16] <= S_AXI_WDATA[23:16];
                    if (S_AXI_WSTRB[3]) mem[axi_awaddr[C_S_AXI_ADDR_WIDTH-1:2]][31:24] <= S_AXI_WDATA[31:24];
                    // Burst Logic: Increment Address
                    axi_awaddr <= axi_awaddr + (C_S_AXI_DATA_WIDTH/8);

                    if(axi_awlen_cntr != 0) begin
                        axi_awlen_cntr <= axi_awlen_cntr - 1;
                        S_AXI_BRESP <= 2'b01;                   // SLVERR by default
                    end
                    else begin
                        S_AXI_WREADY <= 1'b0;                   // Deassert WREADY on last beat
                        axi_aw_active <= 1'b0;
                        S_AXI_BVALID  <= 1'b1;                  // Trigger Response
                        S_AXI_BRESP <= 2'b00;                   // OKAY
                    end
		    axi_data_avail <= 1;                                // Indicate that data is available for processing
                end
            end
            W_RESP: begin
                if (S_AXI_BVALID && S_AXI_BREADY) begin
                    S_AXI_BVALID <= 1'b0;
                end
            end
        endcase
    end
    //=========================================================================================================

    //*********************************************************************************************************
    // read state logic
    reg [C_S_AXI_ADDR_WIDTH-1 : 0] axi_araddr;
    reg [7:0]                      axi_arlen_cntr;
    reg                            axi_ar_active; // Read burst in progress

    // state register for read channels
    always_ff @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
        if (!S_AXI_ARESETN)         current_read_state <= R_IDLE;
        else                        current_read_state <= next_read_state;
    end

    // next state logic for read channels
    always_comb begin
        case (current_read_state)
            R_IDLE: begin
                if (S_AXI_ARVALID) next_read_state = R_ADDR;
            end
            R_ADDR: begin
              if (S_AXI_ARREADY && S_AXI_ARVALID) next_read_state = R_DATA;
            end
            R_DATA: begin
                if (S_AXI_RLAST) next_read_state = R_IDLE;
            end
            default: next_read_state = R_IDLE;
        endcase
    end

    // output logic for read channels
    always_ff @(posedge S_AXI_ACLK) begin
        case (current_read_state)
            R_IDLE: begin
                S_AXI_ARREADY   <= 1'b0;
                S_AXI_RVALID    <= 1'b0;
                S_AXI_RLAST     <= 1'b0;
                axi_ar_active   <= 1'b0;
                axi_arlen_cntr  <= 8'b0;
                S_AXI_RID       <= 0;
                S_AXI_RDATA     <= 0;
                S_AXI_RRESP     <= 2'b01;       // SLVERR by default
            end
            R_ADDR: begin
                axi_araddr     <= S_AXI_ARADDR;
                S_AXI_ARREADY  <= 1'b1;         // Assert ARREADY to accept address
                axi_arlen_cntr <= S_AXI_ARLEN;
                S_AXI_RID      <= S_AXI_ARID;
                axi_ar_active  <= 1'b1;
            end
            R_DATA: begin
                S_AXI_ARREADY <= 1'b0;          // Deassert ARREADY after address accepted
                if (axi_ar_active) begin
                    if(!S_AXI_RVALID || (S_AXI_RVALID && S_AXI_RREADY)) begin
                        S_AXI_RVALID   <= 1'b1;                                         // Assert RVALID to send data
                        S_AXI_RDATA    <= mem_out[axi_araddr[C_S_AXI_ADDR_WIDTH-1:2]];  // Read from memory
                        axi_araddr     <= axi_araddr + (C_S_AXI_DATA_WIDTH/8);          // Increment address
                        if(S_AXI_RVALID)    S_AXI_RRESP    <= 2'b00;                    // OKAY
                        if(axi_arlen_cntr != 0) begin
                            axi_arlen_cntr <= axi_arlen_cntr - 1;
                            S_AXI_RLAST    <= 1'b0;                                     // Deassert RLAST
                        end else begin
                            S_AXI_RLAST     <= 1'b1;                                     // Assert RLAST on last beat
                            axi_ar_active   <= 1'b0;
                        end
                    end
                end
              if(axi_ar_active == 1'b0 && S_AXI_RVALID && S_AXI_RREADY) begin
                    S_AXI_RVALID <= 1'b0;                                               // Deassert RVALID after last beat is accepted
                    S_AXI_RLAST  <= 1'b0;
                end
            end
        endcase
    end
    //*********************************************************************************************************
endmodule
