// ============================================================================
// commit_monitor — logs register write-backs ("x<rd> 0x<data>") to the file
// given by +TRACE=<file>. Meant to be diffed against a reference model's
// commit log (e.g. Spike --log-commits) once a PC/retire port exists.
// ============================================================================
`timescale 1ns/1ps
module commit_monitor (
    input logic        clk,
    input logic        reset,
    input logic        wb_we,
    input logic [4:0]  wb_rd,
    input logic [31:0] wb_data
);
    int    fd = 0;
    string path;

    initial begin
        if ($value$plusargs("TRACE=%s", path)) begin
            fd = $fopen(path, "w");
            if (fd == 0) $display("TB WARNING: cannot open trace file %s", path);
        end
    end

    always @(posedge clk) begin
        if (fd != 0 && !reset && wb_we && wb_rd != 5'd0)
            $fdisplay(fd, "x%0d 0x%08h", wb_rd, wb_data);
    end

    final if (fd != 0) $fclose(fd);
endmodule
