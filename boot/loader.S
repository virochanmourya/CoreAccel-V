// ============================================================================
// CoreAccel-V boot ROM: UART loader (0x0001_0000, 4 KB, BOOT=rom builds)
//
// Register-only RV32I code: no stack and no TCM use, so frames may target
// all of TCM. Reached from the reset vector (RESET_VECTOR = 0x0001_0000).
//
// Boot mode (system control BOOT[1:0], latched from the straps at reset):
//   1        jump to 0x0000_0000 (IMEM already holds the program)
//   0, 2, 3  load over UART0 (2/3 are reserved for SPI flash, today the
//            same as 0)
//
// UART protocol (UART0, 8N1 at its reset divisor; words little-endian):
//   host -> "CAVB" (0x43 0x41 0x56 0x42)       target -> ACK 0x06
//           any other byte: ERR 0xE1, the RX FIFO is flushed and the loader
//           waits for the magic again
//   host -> frame: addr(4) len(4) data(len) crc(4)
//           crc = CRC-32 (zlib: reflected 0xEDB88320, init and final xor
//           0xFFFFFFFF) over addr, len and data
//           addr and len word aligned, len <= 4096, and addr..addr+len
//           entirely in IMEM (0x0000_0000-0x0000_1FFF, written through the
//           IMEM window at 0x1000_0000 + addr) or in TCM
//           (0x8000_0000-0x8000_0FFF); otherwise ERR 0xE3 and resync
//           data words are stored as they arrive; a bad frame is resent
//           whole and simply rewrites them
//   target -> ACK 0x06 (crc good) or NAK 0x15 (crc bad: host resends the
//           frame). The 4th bad crc in a row is answered ERR 0xE2 instead,
//           and the loader resyncs (waits for the magic)
//   len = 0 is the last frame: addr is the entry point. After its ACK has
//           left the transmitter, the loader jumps there.
//
// Registers: s0 UART0 base, s1 CRC, s2 frame address, s3 frame length,
//            s4 bad-crc count, s5 store pointer, s6 CRC polynomial,
//            t4 frame type, a0 byte, a1 word; ra = link of getc/putc/crc8, t6 = link of
//            getb, t5 = link of get32.
// ============================================================================

#define UART0_BASE  0xC0001000
#define U_TXDATA    0x00        // W: push; R: bit31 = TX FIFO full
#define U_RXDATA    0x04        // R: bit31 = RX empty, else [7:0] popped
#define U_STATUS    0x08        // R: bit0 = TX idle
#define SYSCTL_BOOT 0xC0008008  // [1:0] boot-mode strap
#define IMEM_WIN    0x10000000  // IMEM write window (data bus)
#define IMEM_SIZE   0x2000
#define TCM_BASE    0x80000000
#define TCM_END     0x80001000
#define MAX_LEN     4096
#define MAGIC       0x42564143  // "CAVB", first byte in bits [7:0]

#define ACK         0x06
#define NAK         0x15
#define ERR_MAGIC   0xE1
#define ERR_RETRY   0xE2
#define ERR_RANGE   0xE3
#define MAX_TRIES   4

    .section .text.init, "ax", @progbits
    .globl _start
_start:
    li      s0, UART0_BASE
    li      s6, 0xEDB88320
    li      t0, SYSCTL_BOOT
    lw      t0, 0(t0)
    andi    t0, t0, 3
    li      t1, 1
    bne     t0, t1, sync
    jr      zero                    // boot mode 1: run IMEM

// ---------------------------------------------------------------- magic
sync:
    li      t2, MAGIC
    li      t3, 4
1:  jal     getc
    andi    t1, t2, 0xFF
    bne     a0, t1, bad_magic
    srli    t2, t2, 8
    addi    t3, t3, -1
    bnez    t3, 1b
    li      a0, ACK
    jal     putc
    li      s4, 0

// ---------------------------------------------------------------- frame
frame:
    li      s1, -1                  // CRC init
    jal     t5, get32
    mv      s2, a1                  // addr
    jal     t5, get32
    mv      s3, a1                  // len
    snez    t4, s3                  // t4 = 1: data frame, 0: jump frame
    beqz    s3, check_crc

    or      t0, s2, s3              // word aligned?
    andi    t0, t0, 3
    bnez    t0, bad_range
    li      t1, MAX_LEN
    bltu    t1, s3, bad_range
    add     t2, s2, s3              // end (no wrap: addr checked below)
    li      t1, IMEM_SIZE
    bgeu    s2, t1, 2f
    bltu    t1, t2, bad_range       // IMEM: end <= 0x2000
    li      t1, IMEM_WIN
    add     s5, s2, t1
    j       data
2:  li      t1, TCM_BASE
    bltu    s2, t1, bad_range
    li      t1, TCM_END
    bgeu    s2, t1, bad_range
    bltu    t1, t2, bad_range       // TCM: end <= 0x8000_1000
    mv      s5, s2

data:
    jal     t5, get32
    sw      a1, 0(s5)
    addi    s5, s5, 4
    addi    s3, s3, -4
    bnez    s3, data

check_crc:
    not     s1, s1                  // final xor
    li      t3, 4                   // crc field: 4 bytes, not in the CRC
    li      a1, 0
3:  jal     getc
    srli    a1, a1, 8
    slli    a0, a0, 24
    or      a1, a1, a0
    addi    t3, t3, -1
    bnez    t3, 3b
    bne     a1, s1, bad_crc

    li      s4, 0
    li      a0, ACK
    jal     putc
    bnez    t4, frame               // data frame: next one
    // jump frame: let the ACK leave the transmitter, then run the program
5:  lw      t0, U_STATUS(s0)
    andi    t0, t0, 1
    beqz    t0, 5b
    jr      s2

bad_crc:
    addi    s4, s4, 1
    li      t0, MAX_TRIES
    beq     s4, t0, 6f
    li      a0, NAK
    jal     putc
    j       frame
6:  li      a0, ERR_RETRY
    j       resync

bad_range:
    li      a0, ERR_RANGE
    j       resync

bad_magic:
    li      a0, ERR_MAGIC
resync:
    jal     putc
7:  lw      t0, U_RXDATA(s0)        // flush the RX FIFO
    bgez    t0, 7b
    j       sync

// ---------------------------------------------------------------- helpers
// getc: a0 = next RX byte (waits). Link ra.
getc:
    lw      a0, U_RXDATA(s0)
    bltz    a0, getc
    ret

// putc: send a0 (waits for TX FIFO room). Link ra.
putc:
    lw      t0, U_TXDATA(s0)
    bltz    t0, putc
    sw      a0, U_TXDATA(s0)
    ret

// crc8: s1 = CRC-32 of s1 with byte a0 (bitwise, reflected). Link ra.
crc8:
    xor     s1, s1, a0
    .rept 8
    andi    t0, s1, 1
    neg     t0, t0
    and     t0, t0, s6
    srli    s1, s1, 1
    xor     s1, s1, t0
    .endr
    ret

// getb: a0 = next byte, folded into the CRC. Link t6.
getb:
    jal     getc
    jal     crc8
    jr      t6

// get32: a1 = next little-endian word, folded into the CRC. Link t5.
get32:
    li      a1, 0
    li      t3, 4
8:  jal     t6, getb
    srli    a1, a1, 8
    slli    a0, a0, 24
    or      a1, a1, a0
    addi    t3, t3, -1
    bnez    t3, 8b
    jr      t5
