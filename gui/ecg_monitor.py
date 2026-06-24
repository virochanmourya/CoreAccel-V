"""
CoreAccel-V ECG Monitor — Real-time GUI
Reads UART: ECG BPM ST|ECG BPM ST|...
High-performance: OpenGL backend, 8ms refresh, smooth scrolling waveform
"""
import sys, time, collections, math, threading, re
import serial, serial.tools.list_ports
import numpy as np
from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout,
                             QHBoxLayout, QLabel, QComboBox, QPushButton, QFrame)
from PyQt5.QtCore import Qt, QTimer, pyqtSignal, QObject
from PyQt5.QtGui import QFont, QColor, QPalette, QPainter, QBrush, QLinearGradient, QPainterPath
import pyqtgraph as pg
# Force OpenGL rendering for GPU acceleration
try:
    pg.setConfigOption('useOpenGL', True)
except:
    pass

STATUS_LABELS = {
    0: ("NORMAL SINUS",   "#00e676"),
    1: ("TACHYCARDIA",    "#ff9100"),
    2: ("BRADYCARDIA",    "#ffea00"),
    3: ("PREMATURE BEAT", "#ff6d00"),
    4: ("ASYSTOLE",       "#ff1744"),
    5: ("IRREGULAR",      "#e040fb"),
    6: ("V-FIB / V-TACH", "#ff1744"),
    7: ("SINUS TACHY",    "#ffc400"),
}

WAVE_LEN = 1200  # ~5 seconds at ~225 Hz / 4 = ~56 samples/s


class SerialReader(QObject):
    data_received = pyqtSignal(int, int, int)  # ecg, bpm, status
    status_msg = pyqtSignal(str)

    def __init__(self, port, baud=115200):
        super().__init__()
        self.port = port
        self.baud = baud
        self.running = False
        self.ser = None

    def start(self):
        try:
            self.ser = serial.Serial(self.port, self.baud, timeout=0.5)
            time.sleep(0.1)
            self.running = True
            self.thread = threading.Thread(target=self._read_loop, daemon=True)
            self.thread.start()
            self.status_msg.emit(f"Connected to {self.port}")
            return True
        except Exception as e:
            self.status_msg.emit(f"Error: {e}")
            return False

    def stop(self):
        self.running = False
        try:
            if self.ser and self.ser.is_open:
                self.ser.close()
        except:
            pass

    def _read_loop(self):
        """Parse pipe-delimited: ECG BPM ST|..."""
        buf = ""
        # ECG can be negative, so allow optional minus sign
        pat = re.compile(r'(-?\d+)\s+(\d+)\s+(\d+)\s*\|')
        while self.running:
            try:
                data = self.ser.read(1024)
            except Exception:
                self.running = False
                break
            if not data:
                continue
            buf += data.decode('ascii', errors='ignore')
            last_end = 0
            for m in pat.finditer(buf):
                try:
                    ecg = int(m.group(1))
                    bpm = int(m.group(2))
                    st  = int(m.group(3))
                    self.data_received.emit(ecg, bpm, st)
                except ValueError:
                    pass
                last_end = m.end()
            if last_end > 0:
                buf = buf[last_end:]
            if len(buf) > 8192:
                buf = buf[-512:]


class HeartWidget(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setFixedSize(80, 80)
        self.phase = 0.0
        self.beating = False
        self.color = QColor("#00e676")

    def trigger_beat(self):
        self.beating = True
        self.phase = 0.0

    def set_color(self, c):
        self.color = QColor(c)

    def paintEvent(self, event):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        scale = 1.0
        if self.beating:
            self.phase += 0.12
            if self.phase < math.pi:
                scale = 1.0 + 0.2 * math.sin(self.phase)
            else:
                self.beating = False
        cx, cy = 40, 42
        p.translate(cx, cy); p.scale(scale, scale); p.translate(-cx, -cy)
        p.setPen(Qt.NoPen)
        g = QLinearGradient(40, 10, 40, 70)
        g.setColorAt(0, self.color.lighter(140)); g.setColorAt(1, self.color)
        p.setBrush(QBrush(g))
        path = QPainterPath()
        path.moveTo(40, 68)
        path.cubicTo(10, 48, 2, 28, 18, 16); path.cubicTo(28, 8, 38, 14, 40, 24)
        path.cubicTo(42, 14, 52, 8, 62, 16); path.cubicTo(78, 28, 70, 48, 40, 68)
        p.drawPath(path)
        p.end()


class ECGMonitor(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("CoreAccel-V  \u2764  ECG Monitor")
        self.setMinimumSize(1200, 700)
        self.setStyleSheet("""
            QMainWindow { background-color: #0a0e17; }
            QLabel { color: #c0caf5; }
            QComboBox { background: #1a1e2e; color: #c0caf5; border: 1px solid #3b4261;
                        padding: 4px 8px; border-radius: 4px; font-size: 13px; }
            QComboBox QAbstractItemView { background: #1a1e2e; color: #c0caf5; }
            QPushButton { background: #1a1e2e; color: #7aa2f7; border: 1px solid #3b4261;
                          padding: 6px 18px; border-radius: 6px; font-size: 13px; font-weight: bold; }
            QPushButton:hover { background: #24283b; border-color: #7aa2f7; }
            QPushButton:checked { background: #1f6feb; color: #fff; border-color: #1f6feb; }
        """)

        self.ecg_data = collections.deque([0.0]*WAVE_LEN, maxlen=WAVE_LEN)
        self.bpm = 0
        self.status = 0
        self.reader = None
        self.sample_count = 0
        self.peak_val = 0
        self._pending_status = 0
        self._status_count = 0

        central = QWidget()
        self.setCentralWidget(central)
        layout = QVBoxLayout(central)
        layout.setContentsMargins(12, 8, 12, 8)
        layout.setSpacing(6)

        # Top bar
        top = QHBoxLayout()
        title = QLabel("COREACCEL-V  ECG  MONITOR")
        title.setFont(QFont("Segoe UI", 16, QFont.Bold))
        title.setStyleSheet("color: #7aa2f7; letter-spacing: 3px;")
        top.addWidget(title)
        top.addStretch()
        self.conn_indicator = QLabel("\u25cf OFFLINE")
        self.conn_indicator.setFont(QFont("Segoe UI", 11, QFont.Bold))
        self.conn_indicator.setStyleSheet("color: #ff1744;")
        top.addWidget(self.conn_indicator)
        top.addSpacing(12)
        top.addWidget(QLabel("PORT:"))
        self.port_combo = QComboBox(); self.port_combo.setFixedWidth(200)
        self._refresh_ports()
        top.addWidget(self.port_combo)
        self.btn_connect = QPushButton("CONNECT")
        self.btn_connect.setCheckable(True)
        self.btn_connect.clicked.connect(self._toggle_connect)
        top.addWidget(self.btn_connect)
        btn_r = QPushButton("\u27f3"); btn_r.setFixedWidth(36)
        btn_r.clicked.connect(self._refresh_ports)
        top.addWidget(btn_r)
        layout.addLayout(top)

        # Body
        body = QHBoxLayout(); body.setSpacing(12)

        # Waveform
        wf = QFrame()
        wf.setStyleSheet("QFrame{background:#0d1117;border:1px solid #1e2235;border-radius:8px;}")
        wl = QVBoxLayout(wf); wl.setContentsMargins(4, 4, 4, 4)
        pg.setConfigOptions(antialias=True, background='#0d1117', foreground='#3b4261')
        self.pw = pg.PlotWidget()
        self.pw.showGrid(x=False, y=True, alpha=0.12)
        self.pw.hideAxis('bottom')
        self.pw.getAxis('left').setWidth(65)
        self.pw.getAxis('left').setLabel('ECG (mV)', color='#565f89')
        self.pw.setMouseEnabled(x=False, y=False)
        self.pw.setClipToView(True)
        self.pw.setXRange(0, WAVE_LEN, padding=0)
        # Main trace + glow
        self.curve = self.pw.plot(pen=pg.mkPen('#00e676', width=1.5))
        self.glow  = self.pw.plot(pen=pg.mkPen(color=(0,230,118,25), width=4))
        # Zero line
        self.pw.addLine(y=0, pen=pg.mkPen('#1e2235', width=1, style=Qt.DashLine))
        wl.addWidget(self.pw)
        body.addWidget(wf, stretch=7)

        # Right panel
        right = QVBoxLayout(); right.setSpacing(12)

        # BPM Card
        bc = QFrame(); bc.setFixedWidth(260)
        bc.setStyleSheet("QFrame{background:qlineargradient(x1:0,y1:0,x2:0,y2:1,stop:0 #1a1e2e,stop:1 #141824);border:1px solid #1e2235;border-radius:12px;}")
        bl = QVBoxLayout(bc); bl.setContentsMargins(16, 12, 16, 12)
        bh = QHBoxLayout()
        l = QLabel("HEART RATE"); l.setFont(QFont("Segoe UI", 11))
        l.setStyleSheet("color:#565f89;letter-spacing:2px;")
        bh.addWidget(l); bh.addStretch()
        self.heart = HeartWidget(); bh.addWidget(self.heart)
        bl.addLayout(bh)
        self.bpm_label = QLabel("---")
        self.bpm_label.setFont(QFont("Consolas", 72, QFont.Bold))
        self.bpm_label.setAlignment(Qt.AlignCenter)
        self.bpm_label.setStyleSheet("color: #00e676;")
        bl.addWidget(self.bpm_label)
        u = QLabel("BPM"); u.setFont(QFont("Segoe UI", 14))
        u.setAlignment(Qt.AlignCenter); u.setStyleSheet("color:#565f89;letter-spacing:4px;")
        bl.addWidget(u)
        right.addWidget(bc)

        # Status Card
        sc = QFrame(); sc.setFixedWidth(260)
        sc.setStyleSheet("QFrame{background:qlineargradient(x1:0,y1:0,x2:0,y2:1,stop:0 #1a1e2e,stop:1 #141824);border:1px solid #1e2235;border-radius:12px;}")
        sl = QVBoxLayout(sc); sl.setContentsMargins(16, 12, 16, 16)
        s = QLabel("RHYTHM STATUS"); s.setFont(QFont("Segoe UI", 11))
        s.setStyleSheet("color:#565f89;letter-spacing:2px;"); sl.addWidget(s)
        self.status_label = QLabel("WAITING...")
        self.status_label.setFont(QFont("Segoe UI", 20, QFont.Bold))
        self.status_label.setAlignment(Qt.AlignCenter); self.status_label.setWordWrap(True)
        self.status_label.setStyleSheet("color:#565f89;padding:8px;")
        sl.addWidget(self.status_label)
        self.status_detail = QLabel("")
        self.status_detail.setFont(QFont("Segoe UI", 10))
        self.status_detail.setAlignment(Qt.AlignCenter)
        self.status_detail.setStyleSheet("color:#3b4261;")
        sl.addWidget(self.status_detail)
        right.addWidget(sc)

        # Stats
        stc = QFrame(); stc.setFixedWidth(260)
        stc.setStyleSheet("QFrame{background:#141824;border:1px solid #1e2235;border-radius:12px;}")
        stl = QVBoxLayout(stc); stl.setContentsMargins(16, 10, 16, 10)
        self.stats_label = QLabel("Samples: 0")
        self.stats_label.setFont(QFont("Consolas", 10))
        self.stats_label.setStyleSheet("color:#3b4261;")
        stl.addWidget(self.stats_label)
        right.addWidget(stc)
        right.addStretch()
        body.addLayout(right)
        layout.addLayout(body, stretch=1)

        # 8ms timer = 125 fps
        self.draw_timer = QTimer()
        self.draw_timer.timeout.connect(self._update_plot)
        self.draw_timer.start(8)
        self.ht = QTimer(); self.ht.timeout.connect(self.heart.update); self.ht.start(25)
        self.start_time = time.time()
        self._y_range = 500.0

    def _refresh_ports(self):
        self.port_combo.clear()
        for p in serial.tools.list_ports.comports():
            self.port_combo.addItem(f"{p.device} - {p.description}", p.device)

    def _toggle_connect(self, checked):
        if checked:
            port = self.port_combo.currentData()
            if not port:
                self.btn_connect.setChecked(False); return
            self.reader = SerialReader(port, 115200)
            self.reader.data_received.connect(self._on_data, Qt.QueuedConnection)
            self.reader.status_msg.connect(self._on_msg, Qt.QueuedConnection)
            if self.reader.start():
                self.btn_connect.setText("DISCONNECT")
                self.conn_indicator.setText("\u25cf LIVE"); self.conn_indicator.setStyleSheet("color:#00e676;")
                self.start_time = time.time()
                self.sample_count = 0; self.peak_val = 0
            else:
                self.btn_connect.setChecked(False)
        else:
            if self.reader: self.reader.stop()
            self.btn_connect.setText("CONNECT")
            self.conn_indicator.setText("\u25cf OFFLINE"); self.conn_indicator.setStyleSheet("color:#ff1744;")

    def _on_msg(self, msg):
        self.status_detail.setText(msg)

    # ADS1115 at PGA=2.048V: 1 LSB = 0.0625 mV
    MV_SCALE = 0.0625

    def _on_data(self, ecg, bpm, status):
        mv = float(ecg) * self.MV_SCALE
        self.ecg_data.append(mv)
        self.sample_count += 1
        av = abs(mv)
        if av > self.peak_val: self.peak_val = round(av, 1)

        if bpm > 0 and bpm != self.bpm:
            self.heart.trigger_beat()
        if bpm > 0:
            self.bpm = bpm
            self.bpm_label.setText(str(bpm))
            c = "#ff9100" if bpm > 100 else ("#ffea00" if bpm < 55 else "#00e676")
            self.bpm_label.setStyleSheet(f"color:{c};")

        # Debounce status: require 3 consecutive same readings before changing
        if status != self.status:
            if status == self._pending_status:
                self._status_count += 1
            else:
                self._pending_status = status
                self._status_count = 1
            if self._status_count >= 3:
                self.status = status
                lb, co = STATUS_LABELS.get(status, ("UNKNOWN", "#565f89"))
                self.status_label.setText(lb)
                self.status_label.setStyleSheet(f"color:{co};padding:8px;")
                self.heart.set_color(co)
                if status == 4:
                    self.bpm_label.setText("---"); self.bpm_label.setStyleSheet("color:#ff1744;")
        dt = {0:"Normal rhythm",1:"Elevated rate",2:"Low rate",3:"Premature",
              4:"NO HEARTBEAT",5:"Irregular",6:"CRITICAL",7:"Mild elevation"}
        self.status_detail.setText(dt.get(self.status, ""))

    def _update_plot(self):
        d = np.array(self.ecg_data, dtype=np.float64)
        # Remove DC offset — subtract mean to center waveform at 0
        dc = d.mean()
        d = d - dc
        self.curve.setData(d)
        self.glow.setData(d)
        # Track peak-to-peak amplitude
        pk = float(d.max() - d.min())
        if pk > 0:
            self.peak_val = round(pk, 1)
        # Symmetric Y range centered on 0, in mV
        mx = max(float(np.abs(d).max()), 5.0)
        target = mx * 1.4
        self._y_range += (target - self._y_range) * 0.05
        self.pw.setYRange(-self._y_range, self._y_range, padding=0)
        el = int(time.time() - self.start_time)
        self.stats_label.setText(f"Samples: {self.sample_count} | Pk-Pk: {self.peak_val} mV | {el}s")

    def closeEvent(self, e):
        if self.reader: self.reader.stop()
        e.accept()


if __name__ == '__main__':
    app = QApplication(sys.argv)
    app.setStyle('Fusion')
    dp = QPalette()
    dp.setColor(QPalette.Window, QColor("#0a0e17"))
    dp.setColor(QPalette.WindowText, QColor("#c0caf5"))
    app.setPalette(dp)
    w = ECGMonitor()
    w.showMaximized()
    sys.exit(app.exec_())
