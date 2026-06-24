/* main.c -- Pan-Tompkins + Simple Rising-Edge Detector + Classifier
 * Dead-simple detector: rising edge crossing + blanking period.
 * CANNOT get stuck. No state machine. */
#include <stdint.h>
#include "ads1115_driver.h"
#include "uart_driver.h"
#include "seg_driver.h"

static void delay_loops(uint32_t count) {
    for (volatile uint32_t i = 0; i < count; i++)
        __asm__ volatile ("");
}

static int32_t dc_acc = 0;
static int dc_ready = 0;
static int16_t __attribute__((noinline)) remove_dc(int16_t raw) {
    if (!dc_ready) { dc_acc = (int32_t)raw << 8; dc_ready = 1; return 0; }
    dc_acc += (int32_t)raw - (dc_acc >> 8);
    int32_t ac = (int32_t)raw - (dc_acc >> 8);
    if (ac > 32767) ac = 32767;
    if (ac < -32768) ac = -32768;
    return (int16_t)ac;
}

#define LP_TAPS 11
static int32_t lp_buf[LP_TAPS];
static int lp_i = 0;
static int32_t __attribute__((noinline)) lowpass_fir(int32_t x_in) {
    lp_buf[lp_i] = x_in;
    int i0=lp_i;
    int i1=lp_i-1;  if(i1<0) i1+=LP_TAPS;
    int i2=lp_i-2;  if(i2<0) i2+=LP_TAPS;
    int i3=lp_i-3;  if(i3<0) i3+=LP_TAPS;
    int i4=lp_i-4;  if(i4<0) i4+=LP_TAPS;
    int i5=lp_i-5;  if(i5<0) i5+=LP_TAPS;
    int i6=lp_i-6;  if(i6<0) i6+=LP_TAPS;
    int i7=lp_i-7;  if(i7<0) i7+=LP_TAPS;
    int i8=lp_i-8;  if(i8<0) i8+=LP_TAPS;
    int i9=lp_i-9;  if(i9<0) i9+=LP_TAPS;
    int i10=lp_i-10; if(i10<0) i10+=LP_TAPS;
    int32_t y = lp_buf[i0] + (lp_buf[i1]<<1)
        + (lp_buf[i2]+(lp_buf[i2]<<1)) + (lp_buf[i3]<<2)
        + (lp_buf[i4]+(lp_buf[i4]<<2)) + ((lp_buf[i5]<<1)+(lp_buf[i5]<<2))
        + (lp_buf[i6]+(lp_buf[i6]<<2)) + (lp_buf[i7]<<2)
        + (lp_buf[i8]+(lp_buf[i8]<<1)) + (lp_buf[i9]<<1) + lp_buf[i10];
    lp_i++; if (lp_i >= LP_TAPS) lp_i = 0;
    return y >> 5;
}

#define HP_TAPS 33
static int32_t hp_buf[HP_TAPS];
static int hp_wi = 0;
static int32_t hp_sum = 0;
static int32_t __attribute__((noinline)) highpass_fir(int32_t x_in) {
    int32_t x_old = hp_buf[hp_wi];
    hp_buf[hp_wi] = x_in;
    hp_sum = hp_sum + x_in - x_old;
    int ci = hp_wi - 16; if (ci < 0) ci += HP_TAPS;
    hp_wi++; if (hp_wi >= HP_TAPS) hp_wi = 0;
    return hp_buf[ci] - (hp_sum >> 5);
}

#define DV_TAPS 5
static int32_t dv_buf[DV_TAPS];
static int dv_i = 0;
static int32_t __attribute__((noinline)) derivative(int32_t x_in) {
    dv_buf[dv_i] = x_in;
    int i0 = dv_i;
    int i1 = dv_i - 1; if (i1 < 0) i1 += DV_TAPS;
    int i3 = dv_i - 3; if (i3 < 0) i3 += DV_TAPS;
    int i4 = dv_i - 4; if (i4 < 0) i4 += DV_TAPS;
    int32_t d = -dv_buf[i4] - (dv_buf[i3] << 1) + (dv_buf[i1] << 1) + dv_buf[i0];
    dv_i++; if (dv_i >= DV_TAPS) dv_i = 0;
    d = d >> 3;
    if (d > 500) d = 500;
    if (d < -500) d = -500;
    return d;
}

static int32_t __attribute__((noinline)) square_shift(int32_t d) {
    int32_t a = (d < 0) ? -d : d;
    int32_t r = 0;
    if (a & 0x001) r += a;
    if (a & 0x002) r += (a << 1);
    if (a & 0x004) r += (a << 2);
    if (a & 0x008) r += (a << 3);
    if (a & 0x010) r += (a << 4);
    if (a & 0x020) r += (a << 5);
    if (a & 0x040) r += (a << 6);
    if (a & 0x080) r += (a << 7);
    if (a & 0x100) r += (a << 8);
    return r;
}

#define MWI_WIDTH 32
static int32_t mwi_buf[MWI_WIDTH];
static int mwi_wi = 0;
static int32_t mwi_sum = 0;
static int32_t __attribute__((noinline)) mwi(int32_t sq_in) {
    int32_t old = mwi_buf[mwi_wi];
    mwi_buf[mwi_wi] = sq_in;
    mwi_sum = mwi_sum + sq_in - old;
    mwi_wi++; if (mwi_wi >= MWI_WIDTH) mwi_wi = 0;
    int32_t result = mwi_sum >> 5;
    return (result < 0) ? 0 : result;
}

/* Detector: just prev_mi and blanking counter */
static int32_t det_prev = 0;
static int     det_blank = 0;

/* Classifier */
static int32_t cl_rr = 0;
static int32_t cl_rr_avg = 0;
static int     cl_beats = 0;
static int     cl_valid = 0;
static int     cl_chaos = 0;
static int     cl_bpm_slow = 0;
static int     cl_bpm = 0;
static int     cl_status = 0;

#define DET_THRESH  1500
#define BLANK_TIME  100
#define ASYSTOLE_TH 2000
#define MIN_RR      80

int main(void) {
    seg_write_raw(0x0001);
    delay_loops(1000000);
    ads1115_init();
    seg_write_raw(0x0002);
    delay_loops(500000);
    for (int i = 0; i < 50; i++) { remove_dc(ads1115_read()); delay_loops(50000); }

    for (int i = 0; i < LP_TAPS; i++) lp_buf[i] = 0;
    for (int i = 0; i < HP_TAPS; i++) hp_buf[i] = 0;
    hp_wi = 0; hp_sum = 0;
    for (int i = 0; i < DV_TAPS; i++) dv_buf[i] = 0;
    dv_i = 0;
    for (int i = 0; i < MWI_WIDTH; i++) mwi_buf[i] = 0;
    mwi_wi = 0; mwi_sum = 0;

    det_prev = 0; det_blank = 0;
    cl_rr = 0; cl_rr_avg = 400; cl_beats = 0; cl_valid = 0;
    cl_chaos = 0; cl_bpm_slow = 75; cl_bpm = 0; cl_status = 0;

    seg_write_raw(0x0000);
    int n = 0;

    while (1) {
        int16_t raw = ads1115_read();
        int16_t ac  = remove_dc(raw);
        int32_t lp  = lowpass_fir((int32_t)ac);
        int32_t hp  = highpass_fir(lp);
        int32_t dv  = derivative(hp);
        int32_t sq  = square_shift(dv);
        int32_t mi  = mwi(sq);

        /* ===== SIMPLE DETECTOR: rising edge + blanking ===== */
        int beat = 0;
        cl_rr++;

        if (n >= 200) {
            if (det_blank > 0) {
                det_blank--;
            } else if (mi >= DET_THRESH && det_prev < DET_THRESH) {
                /* Rising edge crossing threshold */
                beat = 1;
                det_blank = BLANK_TIME;
            }
            det_prev = mi;
        }

        /* Asystole */
        if (cl_rr > ASYSTOLE_TH) {
            if (cl_status != 4) {
                cl_status = 4;
                cl_bpm = 0;
                seg_write_raw(0x0000);
            }
        }

        /* Beat detected */
        if (beat && cl_rr > MIN_RR) {
            int32_t rr = cl_rr;

            /* BPM lookup — Fs ≈ 225 Hz, fine granularity */
            int bpm;
            uint16_t bcd;
            if      (rr < 68)  { bpm = 199; bcd = 0x0199; }
            else if (rr < 75)  { bpm = 182; bcd = 0x0182; }
            else if (rr < 82)  { bpm = 166; bcd = 0x0166; }
            else if (rr < 90)  { bpm = 152; bcd = 0x0152; }
            else if (rr < 98)  { bpm = 138; bcd = 0x0138; }
            else if (rr < 107) { bpm = 127; bcd = 0x0127; }
            else if (rr < 117) { bpm = 116; bcd = 0x0116; }
            else if (rr < 126) { bpm = 108; bcd = 0x0108; }
            else if (rr < 135) { bpm = 101; bcd = 0x0101; }
            else if (rr < 143) { bpm = 94;  bcd = 0x0094; }
            else if (rr < 152) { bpm = 89;  bcd = 0x0089; }
            else if (rr < 161) { bpm = 84;  bcd = 0x0084; }
            else if (rr < 170) { bpm = 79;  bcd = 0x0079; }
            else if (rr < 176) { bpm = 77;  bcd = 0x0077; }
            else if (rr < 183) { bpm = 74;  bcd = 0x0074; }
            else if (rr < 190) { bpm = 71;  bcd = 0x0071; }
            else if (rr < 197) { bpm = 69;  bcd = 0x0069; }
            else if (rr < 205) { bpm = 66;  bcd = 0x0066; }
            else if (rr < 214) { bpm = 63;  bcd = 0x0063; }
            else if (rr < 225) { bpm = 61;  bcd = 0x0061; }
            else if (rr < 237) { bpm = 57;  bcd = 0x0057; }
            else if (rr < 252) { bpm = 54;  bcd = 0x0054; }
            else if (rr < 270) { bpm = 51;  bcd = 0x0051; }
            else if (rr < 290) { bpm = 47;  bcd = 0x0047; }
            else if (rr < 338) { bpm = 42;  bcd = 0x0042; }
            else if (rr < 450) { bpm = 33;  bcd = 0x0033; }
            else               { bpm = 22;  bcd = 0x0022; }
            cl_bpm = bpm;

            /* Chaos — relaxed to avoid false IRREGULAR triggers */
            if (cl_valid) {
                int32_t diff;
                if (rr > cl_rr_avg) diff = rr - cl_rr_avg;
                else diff = cl_rr_avg - rr;
                if (diff > (cl_rr_avg >> 2)) {
                    if (cl_chaos < 100) cl_chaos += 8;
                } else {
                    if (cl_chaos >= 8) cl_chaos -= 8;
                    else cl_chaos = 0;
                }
            }

            /* Classification */
            if (cl_valid) {
                if (bpm > 180) cl_status = 6;
                else if (cl_chaos > 80) cl_status = 5;
                else if (bpm > 100) cl_status = 1;
                else if (bpm < 55) cl_status = 2;
                else cl_status = 0;
                cl_rr_avg = (cl_rr_avg - (cl_rr_avg >> 3)) + (rr >> 3);
                cl_bpm_slow = (cl_bpm_slow - (cl_bpm_slow >> 5)) + (bpm >> 5);
            } else {
                cl_beats++;
                if (cl_beats > 5) {
                    cl_valid = 1;
                    cl_rr_avg = rr;
                    cl_bpm_slow = bpm;
                }
                cl_status = 0;
            }

            cl_rr = 0;
            seg_write_raw(bcd);
        }

        /* Send every 4th sample: ECG BPM ST| */
        if ((n & 3) == 0) {
            uart_print_int(lp);
            uart_send_byte(' ');
            uart_print_int((int32_t)cl_bpm);
            uart_send_byte(' ');
            uart_print_int((int32_t)cl_status);
            uart_send_byte('|');
        }
        n++;
        delay_loops(50000);
    }
    return 0;
}
