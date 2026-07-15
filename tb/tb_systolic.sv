`timescale 1ns/1ps
`include "systolic_array.sv"
`include "shift_register.sv"
module tb_systolic();

    // Parameters
    localparam int GRID_DIM = 8;
    localparam int ACT_WIDTH = 8;
    localparam int WT_WIDTH = 8;
    localparam int ACC_WIDTH = 32;
    localparam int CLK_PERIOD = 10;

    // Testbench signals
    logic                                           clk;
    logic                                           resetn;
    logic                                           en;
    logic                                           weights_avail;
    logic signed [GRID_DIM-1:0][WT_WIDTH-1:0]     weight_buffer;
    logic signed [GRID_DIM-1:0][ACT_WIDTH-1:0]    act_buffer;
    logic signed [GRID_DIM-1:0][ACC_WIDTH-1:0]    result;
    logic                                           done;
    logic                                           ready;

    // Test vectors
    logic signed [ACT_WIDTH-1:0]  test_activations [GRID_DIM];
    logic signed [WT_WIDTH-1:0]   test_weights [GRID_DIM];
    logic signed [ACC_WIDTH-1:0]  expected_result [GRID_DIM];

    // Test counters
    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;

    // Instantiate DUT
    systolic_array #(
        .GRID_DIM(GRID_DIM),
        .ACT_WIDTH(ACT_WIDTH),
        .WT_WIDTH(WT_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .clk(clk),
        .resetn(resetn),
        .en(en),
        .weights_avail(weights_avail),
        .weight_buffer(weight_buffer),
        .act_buffer(act_buffer),
        .result(result),
        .done(done),
        .ready(ready)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Main testbench logic
    initial begin
        $display("========================================");
        $display("  Systolic Array Testbench");
        $display("========================================");
        
        // Test 1: Reset verification
        //test_reset();
        
        // Test 2: State machine and ready signal
        //test_state_machine();
        
        // Test 3: Single row computation (vector-vector dot product)
        test_simple_dot_product();
        
        // Test 4: Multiple sequential operations
        //test_sequential_operations();
        
        // Test 5: Edge cases (zeros, max values)
        //test_edge_cases();

        // Print summary
        print_test_summary();
        $finish;
    end

    // ============================================
    // Task: Reset Verification
    // ============================================
    task test_reset();
        $display("\n[TEST 1] Reset Verification");
        test_count++;
        
        resetn = 0;
        en = 0;
        weights_avail = 0;
        weight_buffer = '{default: 0};
        act_buffer = '{default: 0};
        
        repeat(5) @(posedge clk);
        
        // Check that module is in IDLE state after reset
        if (ready == 1) begin
            $display("✓ Module ready after reset");
            pass_count++;
        end else begin
            $display("✗ Module not ready after reset");
            fail_count++;
        end
        
        if (done == 0) begin
            $display("✓ Done signal is low after reset");
            pass_count++;
        end else begin
            $display("✗ Done signal is high after reset");
            fail_count++;
        end
        
        resetn = 1;
        repeat(2) @(posedge clk);
    endtask

    // ============================================
    // Task: State Machine Verification
    // ============================================
    task test_state_machine();
        $display("\n[TEST 2] State Machine and Ready Signal");
        test_count++;
        
        resetn = 1;
        @(posedge clk);
        
        // Check IDLE state
        if (ready == 1) begin
            $display("✓ Ready signal asserted in IDLE state");
            pass_count++;
        end else begin
            $display("✗ Ready signal not asserted in IDLE");
            fail_count++;
        end
        
        // Trigger transition to LOAD
        weights_avail = 1;
        @(posedge clk);
        
        repeat(10) begin
            @(posedge clk);
        end
        
        // Check COMPUTE state (after LOAD completes)
        if (ready == 0) begin
            $display("✓ Ready signal deasserted when not in IDLE");
            pass_count++;
        end else begin
            $display("✗ Ready signal still asserted outside IDLE");
            fail_count++;
        end
        
        weights_avail = 0;
    endtask

    // ============================================
    // Task: Simple Dot Product Test
    // ============================================
    task test_simple_dot_product();
        $display("\n[TEST 3] Simple Dot Product Computation");
        test_count++;
        
        // Initialize test vectors: weights = [1,2,3,4,5,6,7,8], acts = [1,1,1,1,1,1,1,1]
        for (int i = 0; i < GRID_DIM; i++) begin
            test_weights[i] = i + 1;
            test_activations[i] = 1;
            expected_result[i] = 8*(i + 1);  // Each PE at position i gets sum of weights up to i
        end
        
        resetn = 1;
        @(posedge clk);
	resetn = 0;
	en = 0;
	@(posedge clk);
	resetn = 1;
        
        // Load phase
        weights_avail = 1;
        load_weights(test_weights);
        
        // Compute phase
        en = 1;
        load_activations(test_activations);
        
        // Wait for computation to complete
        wait(done == 1);
        $display("✓ Computation completed (done signal asserted)");
        pass_count++;
        
        @(posedge clk);
        
        // Verify results
        verify_results(expected_result);
        
        en = 0;
        weights_avail = 0;
        repeat(5) @(posedge clk);
    endtask

    // ============================================
    // Task: Sequential Operations
    // ============================================
    task test_sequential_operations();
        $display("\n[TEST 4] Sequential Operations");
        test_count++;
        
        resetn = 1;
        
        // First operation
        for (int i = 0; i < GRID_DIM; i++) begin
            test_weights[i] = 2;
            test_activations[i] = 3;
            expected_result[i] = 6;
        end
        
        perform_operation(test_weights, test_activations, expected_result);
        
        // Second operation
        for (int i = 0; i < GRID_DIM; i++) begin
            test_weights[i] = 5;
            test_activations[i] = 4;
            expected_result[i] = 20;
        end
        
        perform_operation(test_weights, test_activations, expected_result);
        
        $display("✓ Multiple sequential operations completed");
        pass_count++;
    endtask

    // ============================================
    // Task: Edge Cases
    // ============================================
    task test_edge_cases();
        $display("\n[TEST 5] Edge Cases");
        test_count++;
        
        resetn = 1;
        
        // Test with zeros
        for (int i = 0; i < GRID_DIM; i++) begin
            test_weights[i] = 0;
            test_activations[i] = 5;
            expected_result[i] = 0;
        end
        
        perform_operation(test_weights, test_activations, expected_result);
        $display("✓ Zero weights test passed");
        pass_count++;
        
        // Test with maximum values
        for (int i = 0; i < GRID_DIM; i++) begin
            test_weights[i] = 127;
            test_activations[i] = 127;
            expected_result[i] = 127 * 127;
        end
        
        perform_operation(test_weights, test_activations, expected_result);
        $display("✓ Maximum values test passed");
        pass_count++;
    endtask

    // ============================================
    // Helper Tasks
    // ============================================
    task load_weights(logic signed [WT_WIDTH-1:0] weights [GRID_DIM]);
        for (int i = 0; i < GRID_DIM; i++) begin
            weight_buffer[i] = weights[i];
        end
        
        // Wait for weight loading to complete
        repeat(GRID_DIM + 2) @(posedge clk);
    endtask

    task load_activations(logic signed [ACT_WIDTH-1:0] activations [GRID_DIM]);
        for (int i = 0; i < GRID_DIM; i++) begin
            act_buffer[i] = activations[i];
        end
    endtask

    task perform_operation(
        logic signed [WT_WIDTH-1:0] weights [GRID_DIM],
        logic signed [ACT_WIDTH-1:0] activations [GRID_DIM],
        logic signed [ACC_WIDTH-1:0] expected [GRID_DIM]
    );
        // Wait for ready
        wait(ready == 1);
        @(posedge clk);
        
        // Load weights
        weights_avail = 1;
        load_weights(weights);
        weights_avail = 0;
        
        // Wait for ready again
        wait(ready == 1);
        @(posedge clk);
        
        // Perform computation
        en = 1;
        load_activations(activations);
        
        wait(done == 1);
        @(posedge clk);
        
        // Verify
        verify_results(expected);
        
        en = 0;
    endtask

    task verify_results(logic signed [ACC_WIDTH-1:0] expected [GRID_DIM]);
        logic mismatch = 0;
        
        for (int i = 0; i < GRID_DIM; i++) begin
            if (result[i] !== expected[i]) begin
                $display("✗ Result mismatch at index %0d: Got %0d, Expected %0d", 
                    i, result[i], expected[i]);
                mismatch = 1;
                fail_count++;
            end
        end
        
        if (!mismatch) begin
            $display("✓ All results verified correctly");
            pass_count++;
        end
    endtask

    task print_test_summary();
        $display("\n========================================");
        $display("  Test Summary");
        $display("========================================");
        $display("Total Tests: %0d", test_count);
        $display("Passed: %0d", pass_count);
        $display("Failed: %0d", fail_count);
        
        if (fail_count == 0) begin
            $display("\n✓ ALL TESTS PASSED");
        end else begin
            $display("\n✗ SOME TESTS FAILED");
        end
        $display("========================================\n");
    endtask

endmodule

