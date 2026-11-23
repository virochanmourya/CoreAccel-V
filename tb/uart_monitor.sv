// ============================================================================
// uart_monitor — decodes the DUT's 8N1 TX line and prints each line received
// as "UART: <text>". Optional +UARTLOG=<file> captures raw bytes.
// ============================================================================
`timescale 1ns/1ps
module uart_monitor #(
    parameter int CLKS_PER_BIT = 100_000_000 / 115_200
)(
    input logic clk,
    input logic rx
);
    int    fd = 0;
    string path;
    string line = "";

    initial begin
        if ($value$plusargs("UARTLOG=%s", path)) fd = $fopen(path, "w");
    end

    initial begin
        logic [7:0] b;
        forever begin
            @(negedge rx);
            repeat (CLKS_PER_BIT / 2) @(posedge clk);
            if (rx !== 1'b0) continue;              // glitch, not a start bit
            for (int i = 0; i < 8; i++) begin
                repeat (CLKS_PER_BIT) @(posedge clk);
                b[i] = rx;
            end
            repeat (CLKS_PER_BIT) @(posedge clk);   // stop bit
            if (fd != 0) $fwrite(fd, "%c", b);
            if (b == 8'h0A || b == 8'h0D) begin
                if (line.len() != 0) $display("UART: %s", line);
                line = "";
            end else begin
                line = {line, string'(b)};
            end
        end
    end

    final begin
        if (line.len() != 0) $display("UART: %s", line);
        if (fd != 0) $fclose(fd);
    end
endmodule
