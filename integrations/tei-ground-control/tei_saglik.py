"""Sağlık sekmesi: motor çıkışları (SERVO_OUTPUT_RAW), hücreler, titreşim, EKF, rüzgâr ve hover teşhisi.

ESC telemetrisi gerekmez (Skywalker PWM ESC'ler için yazıldı): Pixhawk'ın her motora gönderdiği PWM,
hover sırasında hangi motorun fazla çalıştığını gösterir. Teşhis mantığı (HoverAnaliz) Qt kullanmaz;
drone-simulation/tools/dronebridge/health.py ile aynı kurallar.
"""

import statistics

# Quad-X: ArduPilot motor no -> (ad, dönüş, harita konumu (x, y): x sağ +, y ön +)
MOTORLAR = {1: ("M1 ön-sağ", "CCW", (1, 1)), 2: ("M2 arka-sol", "CCW", (-1, -1)),
            3: ("M3 ön-sol", "CW", (-1, 1)), 4: ("M4 arka-sağ", "CW", (1, -1))}
UYARI, KOTU = 0.06, 0.12


class HoverAnaliz:
    """Havada, sabit dururken motor çıkışlarını toplar ve tek motor sorununu bulur."""

    def __init__(self, en_az_ornek=25):
        self.ornekler = []
        self.en_az = en_az_ornek

    def ekle(self, t):
        pwm = t.motor_pwm[:4]
        havada = t.armed and t.alt_rel > 2 and abs(t.climb) < 0.3 and t.groundspeed < 0.7
        if havada and all(p >= 1000 for p in pwm):
            self.ornekler.append([(p - 1000) / 1000 for p in pwm])
            self.ornekler = self.ornekler[-1500:]

    def profil(self):
        if len(self.ornekler) < self.en_az:
            return None
        return [statistics.fmean(o[i] for o in self.ornekler) for i in range(4)]

    def teshis(self):
        """(seviye 'OK'|'UYARI'|'KÖTÜ'|'BEKLE', metin)"""
        p = self.profil()
        if p is None:
            return "BEKLE", f"Hover verisi toplanıyor ({len(self.ornekler)}/{self.en_az}) — havada sabit durun"
        medyan = statistics.median(p)
        sapma = [abs(x - medyan) / medyan for x in p]
        en = max(range(4), key=lambda k: sapma[k])
        diger = [s for k, s in enumerate(sapma) if k != en]
        ort = statistics.fmean(p)
        if sapma[en] >= UYARI and max(diger) <= sapma[en] / 3:
            oran = p[en] / statistics.fmean(x for k, x in enumerate(p) if k != en)
            ad = MOTORLAR[en + 1][0]
            seviye = "KÖTÜ" if oran - 1 >= KOTU else "UYARI"
            return seviye, (f"{ad} diğerlerinden %{(oran - 1) * 100:.0f} fazla çalışıyor → ≈%{(1 - 1 / oran) * 100:.0f} "
                            f"itki kaybı: pervane (çatlak/balans), motor rulmanı, ESC kontrol edin")
        ccw, cw = (p[0] + p[1]) / 2, (p[2] + p[3]) / 2
        yaw = (ccw - cw) / ort
        if abs(yaw) >= 0.05:
            return "UYARI", f"CCW/CW farkı %{yaw * 100:+.0f} → eğik motor montajı veya yaw trimi"
        if ort >= 0.70:
            return "UYARI", f"Hover gazı %{ort * 100:.0f} — itki payı az (ağır yük / zayıf pervane)"
        return "OK", f"Motorlar dengeli · hover gazı %{ort * 100:.0f} · itki/ağırlık ≈ {1 / ort:.2f}"


try:  # Qt parçası; testler Qt olmadan HoverAnaliz'i kullanabilsin
    from PySide6.QtCore import Qt, QRectF, QPointF
    from PySide6.QtGui import QPainter, QColor, QPen, QFont
    from PySide6.QtWidgets import QWidget

    class SaglikPaneli(QWidget):
        def __init__(self, renkler, parent=None):
            super().__init__(parent)
            self.r = renkler  # {"ok", "warn", "danger", "muted", "accent", "line", "text"}
            self.t = None
            self.analiz = HoverAnaliz()
            self.setMinimumHeight(320)

        def guncelle(self, t):
            self.t = t
            self.analiz.ekle(t)
            self.update()

        def sifirla(self):
            self.analiz = HoverAnaliz()
            self.update()

        def _renk(self, seviye):
            return QColor({"OK": self.r["ok"], "UYARI": self.r["warn"], "KÖTÜ": self.r["danger"]}.get(seviye, self.r["muted"]))

        def paintEvent(self, _):
            p = QPainter(self)
            p.setRenderHint(QPainter.Antialiasing)
            w, h = self.width(), self.height()
            t = self.t
            p.setPen(QColor(self.r["text"]))
            p.setFont(QFont("Segoe UI", 10, QFont.Bold))
            p.drawText(QRectF(12, 8, w - 24, 20), Qt.AlignLeft, "MOTORLAR (SERVO_OUTPUT_RAW · PWM)")
            if t is None or not any(t.motor_pwm):
                p.setPen(QColor(self.r["muted"]))
                p.drawText(QRectF(12, 40, w - 24, 20), Qt.AlignLeft, "Veri yok — bağlanın (SERVO_OUTPUT_RAW bekleniyor)")
                return

            # Üstten görünüş: dört motor, çıkış yüzdesiyle dolan halkalar
            cx, cy, kol = w * 0.28, 150, min(w * 0.18, 95)
            p.setPen(QPen(QColor(self.r["line"]), 6))
            p.drawLine(QPointF(cx - kol, cy - kol), QPointF(cx + kol, cy + kol))
            p.drawLine(QPointF(cx + kol, cy - kol), QPointF(cx - kol, cy + kol))
            p.setPen(QColor(self.r["accent"]))
            p.drawText(QRectF(cx - 40, cy - kol - 34, 80, 16), Qt.AlignCenter, "▲ ÖN")
            for no, (ad, donus, (x, y)) in MOTORLAR.items():
                pwm = t.motor_pwm[no - 1] if len(t.motor_pwm) >= no else 0
                cikis = max(0.0, min(1.0, (pwm - 1000) / 1000)) if pwm else 0.0
                mx, my = cx + x * kol, cy - y * kol
                renk = QColor(self.r["danger"] if cikis >= 0.9 else self.r["warn"] if cikis >= 0.7 else self.r["ok"])
                p.setPen(QPen(QColor(self.r["line"]), 8))
                p.drawEllipse(QPointF(mx, my), 30, 30)
                p.setPen(QPen(renk, 8))
                p.drawArc(QRectF(mx - 30, my - 30, 60, 60), 90 * 16, int(-360 * 16 * cikis))
                p.setPen(QColor(self.r["text"]))
                p.setFont(QFont("Segoe UI", 9, QFont.Bold))
                p.drawText(QRectF(mx - 30, my - 10, 60, 20), Qt.AlignCenter, f"%{cikis * 100:.0f}")
                p.setFont(QFont("Segoe UI", 8))
                p.setPen(QColor(self.r["muted"]))
                p.drawText(QRectF(mx - 50, my + 32, 100, 14), Qt.AlignCenter, f"{ad.split()[0]} {donus} · {pwm}")

            # Sağ sütun: batarya, titreşim, EKF, rüzgâr
            x0, yy = w * 0.56, 36
            satirlar = []
            if t.cells:
                fark = (max(t.cells) - min(t.cells)) * 1000
                satirlar.append(("Hücreler", " · ".join(f"{c:.2f}" for c in t.cells) + f" V  (fark {fark:.0f} mV)",
                                 "UYARI" if fark > 50 else "OK"))
            if t.mah >= 0:
                satirlar.append(("Harcanan", f"{t.mah} mAh", "OK"))
            if any(t.vibe):
                en = max(t.vibe)
                satirlar.append(("Titreşim", "/".join(f"{v:.0f}" for v in t.vibe) + f" m/s² · clip {t.clipping}",
                                 "KÖTÜ" if en >= 60 else "UYARI" if en >= 30 else "OK"))
            else:
                satirlar.append(("Titreşim", "VIBRATION mesajı yok", "BEKLE"))
            if t.ekf_max > 0:
                satirlar.append(("EKF", f"en kötü varyans {t.ekf_max:.2f}",
                                 "KÖTÜ" if t.ekf_max >= 0.8 else "UYARI" if t.ekf_max >= 0.5 else "OK"))
            if t.wind_speed >= 0:
                satirlar.append(("Rüzgâr (tahmin)", f"{t.wind_speed:.1f} m/s · {t.wind_dir:03.0f}°'den",
                                 "UYARI" if t.wind_speed > 10 else "OK"))
            for baslik, deger, seviye in satirlar:
                p.setPen(QColor(self.r["muted"]))
                p.setFont(QFont("Segoe UI", 9))
                p.drawText(QRectF(x0, yy, w - x0 - 12, 16), Qt.AlignLeft, baslik)
                p.setPen(self._renk(seviye))
                p.setFont(QFont("Segoe UI", 10, QFont.Bold))
                p.drawText(QRectF(x0, yy + 16, w - x0 - 12, 18), Qt.AlignLeft, deger)
                yy += 42

            seviye, metin = self.analiz.teshis()
            p.setPen(self._renk(seviye))
            p.setFont(QFont("Segoe UI", 10, QFont.Bold))
            p.drawText(QRectF(12, h - 58, w - 24, 50), Qt.AlignLeft | Qt.TextWordWrap, f"Teşhis: {metin}")

except ImportError:  # pragma: no cover
    SaglikPaneli = None
