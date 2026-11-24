// ============================================================================
// i2c_target_model — I2C register target for the testbench.
// - START / repeated START / STOP detection; 7-bit address, ACK on a match
// - write: first data byte = register pointer, then each byte is stored at
//   regs[ptr] and the pointer increments; every byte is ACKed
// - read: sends regs[ptr], ptr+1, ... MSB first; stops sending after the
//   master's NACK
// - clock stretching: with stretch_ns > 0 it holds SCL low for that long
//   after the falling edge of every ACK clock
// - arbitration test: with al_bit >= 0 it acts as a second master during
//   the next address byte: it pulls SDA low from the SCL fall before bit
//   al_bit (the DUT must be sending a 1 there) for AL_HOLD ns, then lets go
//   and ignores the rest of that transfer
// - bus hog (hog_go): kind 0 holds SDA low with SCL high without a START
//   (SDA falls while SCL is low), kind 1 makes a START and then holds the
//   bus with both lines high; after hog_ns both end (kind 1 with a STOP)
// It drives SCL/SDA open-drain, like a real device, so it exercises the
// DUT's pad input path and synchronisers. Prints one line per address phase.
// regs[] start as REG_SEED + index.
// ============================================================================
`timescale 1ns/1ps
module i2c_target_model #(
    parameter logic [6:0] ADDR     = 7'h48,     // ADS1115 default address
    parameter int         NREGS    = 16,
    parameter logic [7:0] REG_SEED = 8'hA0,
    parameter int         AL_HOLD  = 3000       // ns
)(
    inout wire scl,
    inout wire sda
);
    typedef enum {T_IDLE, T_ADDR, T_WRITE, T_READ, T_IGNORE} tst_t;
    tst_t       tst     = T_IDLE;
    logic       sda_low = 1'b0;
    logic       scl_low = 1'b0;
    int         bitcnt  = 0;          // bits of the current byte (0..9)
    logic [7:0] shreg   = '0;
    logic [7:0] tx      = '0;
    logic       first_w = 1'b0;       // next written byte is the pointer
    logic       mnack   = 1'b0;       // master answered NACK on a read
    int         ptr     = 0;
    logic [7:0] regs [NREGS];
    int         stretch_ns = 0;
    int         al_bit     = -1;
    int         hog_kind   = 0, hog_ns = 0;
    logic       hog_go     = 1'b0;
    int         n_writes = 0, n_reads = 0, n_stretch = 0;

    assign sda = sda_low ? 1'b0 : 1'bz;
    assign scl = scl_low ? 1'b0 : 1'bz;

    initial for (int i = 0; i < NREGS; i++) regs[i] = REG_SEED + 8'(i);

    // START / repeated START: SDA falls while SCL is high
    always @(negedge sda) if (scl === 1'b1 && !sda_low) begin
        tst    = T_ADDR;
        bitcnt = 0;
    end

    // STOP: SDA rises while SCL is high
    always @(posedge sda) if (scl === 1'b1) begin
        tst     = T_IDLE;
        sda_low = 1'b0;
    end

    always @(posedge scl) begin
        if ((tst == T_ADDR || tst == T_WRITE) && bitcnt < 8) begin
            shreg  = {shreg[6:0], (sda === 1'b0) ? 1'b0 : 1'b1};
            bitcnt = bitcnt + 1;
        end else if (tst == T_READ && bitcnt == 8) begin
            mnack  = (sda !== 1'b0);        // master's ACK bit
            bitcnt = 9;
        end else if (tst == T_READ && bitcnt < 8) begin
            bitcnt = bitcnt + 1;
        end
    end

    task automatic arbitrate();
        sda_low = 1'b1;
        al_bit  = -1;
        tst     = T_IGNORE;
        #(AL_HOLD);
        sda_low = 1'b0;
    endtask

    always @(posedge hog_go) begin
        $display("I2C target: bus hog kind %0d for %0d ns", hog_kind, hog_ns);
        if (hog_kind == 0) begin
            scl_low = 1'b1; #200; sda_low = 1'b1; #200; scl_low = 1'b0;
            #(hog_ns);
            scl_low = 1'b1; #200; sda_low = 1'b0; #200; scl_low = 1'b0;
        end else begin
            sda_low = 1'b1; #200; scl_low = 1'b1; #200; sda_low = 1'b0; #200; scl_low = 1'b0;
            #(hog_ns);
            scl_low = 1'b1; #200; sda_low = 1'b1; #200; scl_low = 1'b0; #200; sda_low = 1'b0;
        end
        hog_go = 1'b0;
    end

    task automatic stretch();
        if (stretch_ns > 0) begin
            scl_low = 1'b1;
            n_stretch++;
            #(stretch_ns);
            scl_low = 1'b0;
        end
    endtask

    always @(negedge scl) begin
        case (tst)
            T_ADDR: begin
                if (al_bit >= 0 && bitcnt == al_bit) begin
                    $display("I2C target: second master pulls SDA low at address bit %0d", al_bit);
                    fork arbitrate(); join_none
                end else if (bitcnt == 8) begin            // end of address byte
                    $display("I2C target: addr=0x%02h %s -> %s", shreg[7:1],
                             shreg[0] ? "R" : "W", (shreg[7:1] == ADDR) ? "ACK" : "NACK");
                    if (shreg[7:1] == ADDR) begin
                        sda_low = 1'b1;
                        bitcnt  = 9;
                    end else begin
                        tst = T_IGNORE;
                    end
                end else if (bitcnt == 9) begin            // end of ACK clock
                    sda_low = 1'b0;
                    bitcnt  = 0;
                    if (shreg[0]) begin
                        tst = T_READ;
                        tx  = regs[ptr % NREGS];
                        sda_low = ~tx[7];
                    end else begin
                        tst     = T_WRITE;
                        first_w = 1'b1;
                    end
                    stretch();
                end
            end
            T_WRITE: begin
                if (bitcnt == 8) begin
                    if (first_w) ptr = shreg;
                    else begin
                        regs[ptr % NREGS] = shreg;
                        ptr = ptr + 1;
                        n_writes++;
                    end
                    first_w = 1'b0;
                    sda_low = 1'b1;                       // ACK
                    bitcnt  = 9;
                end else if (bitcnt == 9) begin
                    sda_low = 1'b0;
                    bitcnt  = 0;
                    stretch();
                end
            end
            T_READ: begin
                if (bitcnt < 8 && bitcnt > 0) begin
                    sda_low = ~tx[7 - bitcnt];
                end else if (bitcnt == 8) begin
                    sda_low = 1'b0;                       // release for the master's ACK
                    ptr = ptr + 1;
                    n_reads++;
                end else if (bitcnt == 9) begin
                    bitcnt = 0;
                    if (mnack) begin
                        tst = T_IGNORE;                   // wait for STOP / START
                    end else begin
                        tx      = regs[ptr % NREGS];
                        sda_low = ~tx[7];
                        stretch();
                    end
                end
            end
            default: ;
        endcase
    end
endmodule
