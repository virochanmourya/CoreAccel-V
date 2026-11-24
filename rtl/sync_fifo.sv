// ============================================================================
// Module      : sync_fifo
// File        : sync_fifo.sv
// Description : Small single-clock FIFO in flops (peripheral FIFOs).
//               Show-ahead: rdata is the head entry while !empty.
//               A push when full or a pop when empty is ignored. A push and
//               a pop in the same cycle are both done (also when full).
// ============================================================================

module sync_fifo #(
    parameter int WIDTH = 8,
    parameter int DEPTH = 16,                 // power of two
    localparam int AW   = $clog2(DEPTH)
)(
    input  logic             clk,
    input  logic             reset,
    input  logic             push,
    input  logic [WIDTH-1:0] wdata,
    input  logic             pop,
    output logic [WIDTH-1:0] rdata,
    output logic             empty,
    output logic             full,
    output logic [AW:0]      level
);

    logic [WIDTH-1:0] mem [DEPTH];
    logic [AW-1:0]    wp, rp;
    logic             do_push, do_pop;

    assign empty   = (level == '0);
    assign full    = (level == (AW+1)'(DEPTH));
    assign do_pop  = pop & ~empty;
    assign do_push = push & (~full | do_pop);
    assign rdata   = mem[rp];

    always_ff @(posedge clk) begin
        if (reset) begin
            wp    <= '0;
            rp    <= '0;
            level <= '0;
        end else begin
            if (do_push) wp <= wp + 1'b1;
            if (do_pop)  rp <= rp + 1'b1;
            case ({do_push, do_pop})
                2'b10:   level <= level + 1'b1;
                2'b01:   level <= level - 1'b1;
                default: ;
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (do_push) mem[wp] <= wdata;
    end

endmodule
