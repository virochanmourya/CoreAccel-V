// ============================================================================
// spi_flash_model — minimal SPI NOR flash for the testbench (modes 0 and 3).
// Commands: 0x9F read ID (3 bytes, JEDEC_ID MSB first, then repeats),
//           0x03 read data (24-bit address, then bytes from addr, +1 each).
// Any other command is ignored until CS rises. MOSI is sampled on SCK
// rising edges, MISO changes on SCK falling edges (and when CS falls); MISO
// floats while CS is high. Memory byte at address a = MEM_SEED ^ a[7:0] ^ a[15:8].
// Checks: SCK must be known when CS falls and back at that idle level when
// CS rises (whole bytes, no stray edge); a violation calls tb_top.sva_fail().
// SCK edges while CS is high are ignored (another device's transfer).
// ============================================================================
`timescale 1ns/1ps
module spi_flash_model #(
    parameter logic [23:0] JEDEC_ID = 24'hC2_20_17,
    parameter logic [7:0]  MEM_SEED = 8'h3C
)(
    input  wire cs_n,
    input  wire sck,
    input  wire mosi,
    output wire miso
);
    logic        miso_q  = 1'b0;
    logic        drive   = 1'b0;
    int          bitcnt  = 0;          // bits received since CS fell
    logic [7:0]  in_sh   = '0;
    logic [7:0]  cmd     = '0;
    logic [23:0] addr    = '0;
    logic [7:0]  out_sh  = '0;
    int          out_bit = 0;          // next bit index to drive (7..0)
    logic        idle_level;
    int          n_cmds = 0;
    bit          selected = 1'b0;      // a CS fall was seen (not the reset X -> 1)

    assign miso = drive ? miso_q : 1'bz;

    function automatic logic [7:0] mem_byte(input logic [23:0] a);
        return MEM_SEED ^ a[7:0] ^ a[15:8];
    endfunction

    // Next byte to send, once bitcnt bits have been received (a byte boundary).
    function automatic logic [7:0] next_out(input int nbits);
        int nb = nbits / 8;                 // bytes received so far
        if (cmd == 8'h9F && nb >= 1) begin
            case ((nb - 1) % 3)
                0: return JEDEC_ID[23:16];
                1: return JEDEC_ID[15:8];
                default: return JEDEC_ID[7:0];
            endcase
        end
        if (cmd == 8'h03 && nb >= 4) return mem_byte(addr + 24'(nb - 4));
        return 8'hFF;
    endfunction

    always @(negedge cs_n) begin
        selected   = 1'b1;
        idle_level = sck;
        bitcnt  = 0;
        cmd     = '0;
        drive   = 1'b1;
        out_sh  = 8'hFF;
        out_bit = 7;
        miso_q  = 1'b1;
    end

    always @(posedge cs_n) begin
        drive = 1'b0;
        if (selected && sck !== idle_level) begin
            $display("SPI flash: SCK not idle at CS rise t=%0t", $time);
            tb_top.sva_fail();
        end
    end

    always @(posedge sck) begin
        if (cs_n === 1'b0) begin
            in_sh  = {in_sh[6:0], (mosi === 1'b1)};
            bitcnt = bitcnt + 1;
            if (bitcnt == 8) begin
                cmd = in_sh;
                n_cmds++;
                $display("SPI flash: cmd 0x%02h", cmd);
            end
            if (cmd == 8'h03 && bitcnt >= 16 && bitcnt <= 32 && bitcnt % 8 == 0)
                addr = {addr[15:0], in_sh};
        end
    end

    always @(negedge sck) begin
        if (cs_n === 1'b0 && bitcnt > 0) begin
            if (bitcnt % 8 == 0) begin
                out_sh  = next_out(bitcnt);
                out_bit = 7;
            end
            miso_q  = out_sh[out_bit];
            out_bit = out_bit - 1;
        end
    end

    // Mode check: only modes 0 and 3 (sample on rising edges).
    always @(negedge cs_n) begin
        #0;
        if (sck !== 1'b0 && sck !== 1'b1) begin
            $display("SPI flash: SCK unknown at CS fall t=%0t", $time);
            tb_top.sva_fail();
        end
    end
endmodule
