# 🛡️ BDRman v3.0 - Complete Security Suite

## 🎉 YENİ ÖZELLİKLER

### 1️⃣ Otomatik Güvenlik İzleme Sistemi (Real-time)

**Her 2 saniyede bir kontrol edilenler:**

- 🚨 DDoS saldırıları (bağlantı flooding)
- ⚡ Yüksek CPU kullanımı (>90%)
- 🧠 Yüksek bellek kullanımı (>90%)
- 💾 Kritik disk doluluk (>90%)
- 🔐 Brute force giriş denemeleri
- ⚙️ Servis kesintileri

**Kurulum:**

```bash
bdrman
→ 7) Security & Hardening
→ 8) Setup Advanced Monitoring
```

**Telegram Uyarı Örneği:**

```
🚨 DDOS ALERT DETECTED

⚠️ Threat Level: HIGH
📊 Type: Connection Flood
🔍 Details:
   • Suspicious IPs: 3
   • Top Offender: 192.168.1.100
   • Connections: 156

💡 Recommended Actions:
   1. /ddos_enable - Enable DDoS protection
   2. /caprover_protect - Protect CapRover
   3. /block 192.168.1.100 - Block this IP

📅 Time: 2024-11-07 14:30:25
```

---

### 2️⃣ Kapsamlı Güvenlik Araçları Paketi

**Otomatik Kurulan Araçlar:**

#### 🔒 **Fail2Ban** - Brute Force Koruması

- SSH saldırılarını bloklar
- Nginx authentication koruması
- Otomatik IP ban

#### 🦠 **ClamAV** - Antivirüs

- Gerçek zamanlı virüs taraması
- Otomatik tanım güncellemesi
- Zamanlanmış taramalar

#### 🕵️ **RKHunter** - Rootkit Detector

- Rootkit tespiti
- Sistem dosya bütünlüğü kontrolü
- Zararlı yazılım taraması

#### 📊 **Lynis** - Güvenlik Audit

- Sistem güvenlik puanlaması
- Detaylı güvenlik önerileri
- Compliance kontrolleri

#### 🛡️ **AppArmor** - Mandatory Access Control

- Uygulama yetkilendirme
- Sandbox koruması
- Sistem politikaları

#### 🔍 **Aide** - File Integrity

- Dosya değişiklik tespiti
- Yetkisiz erişim kontrolü
- Sistem bütünlüğü

#### 📝 **Auditd** - Linux Audit Framework

- Sistem aktivite logu
- Güvenlik olayları kaydı
- Forensic analiz

#### 🔎 **Psad** - Port Scan Detector

- Port tarama tespiti
- Iptables log analizi
- Otomatik engelleme

**Kurulum (Tek Komut):**

```bash
bdrman
→ 7) Security & Hardening
→ 5) Install ALL Security Tools
```

**Tarama Çalıştırma:**

```bash
bdrman
→ 7) Security & Hardening
→ 6) Run Security Scan
```

---

### 3️⃣ Emergency Mode Exit (Yeni!)

**Önceden:** Emergency mode'a girince çıkış zordu
**Şimdi:** Tek komutla normal moda dönüş!

**Ana Menüden:**

```bash
bdrman
→ 10) Incident Response
→ 3) Exit Emergency Mode
```

**Telegram'dan:**

```
/emergency_exit
```

**Ne Yapar:**

- ✅ Durdurulan servisleri tekrar **başlatır** (yeniden yüklemez!)
- ✅ Docker container'ları **çalıştırır** (rebuild etmez!)
- ✅ Firewall portlarını **yeniden açar** (80, 443, 3000)
- ✅ Hiçbir veri silinmez, hiçbir şey yeniden kurulmaz!

**UYARI:** Bu sadece emergency mode'un tersini yapar:

- Emergency mode → Servisleri DURDUR, firewall KAPAT
- Emergency exit → Servisleri BAŞLAT, firewall AÇ

---

### 4️⃣ Eğlenceli & Yararlı Telegram Komutları

#### 😄 Eğlence Komutları

**`/joke`** - Sunucu şakası

```
😄 Server Joke Time!

Why do programmers prefer dark mode? 🌙
Because light attracts bugs! 🐛
```

**`/fortune`** - Falın

```
🔮 Server Fortune

Everything will run smoothly today! 🍀
```

**`/cowsay [text]`** - İnek ne diyor?

```
🐮 Cow Says:

 _____________________
< Your server rocks! >
 ---------------------
        \   ^__^
         \  (oo)\_______
            (__)\       )\/\
                ||----w |
                ||     ||
```

**`/funstats`** - Eğlenceli istatistikler

```
🎉 Fun Server Stats!

🖥️ Your Server: my-server
⏱️ Been running for: 12 days
🐧 Kernel: 5.15.0-94-generic

🎲 Fun Facts:
• You have 1,234,567 files!
• And 89,012 directories!
```

**`/ascii`** - ASCII Art

```
    _____ ______ _______      ________ _____
   / ____|  ____|  __ \ \    / /  ____|  __ \
  | (___ | |__  | |__) \ \  / /| |__  | |__) |
   \___ \|  __| |  _  /  \ \/ / |  __| |  _  /
   ____) | |____| | \ \   \  /  | |____| | \ \
  |_____/|______|_|  \_\   \/   |______|_|  \_\

       POWERED BY BDRMAN 🚀
```

**`/tip`** - Rastgele sunucu ipucu

```
💡 Tip: Enable DDoS protection with /ddos_enable
```

---

### 5️⃣ Güncel Komut Listesi (v3.0)

#### 📊 Monitoring (Değişiklik Yok)

```
/status, /health, /docker, /containers
/services, /logs, /disk, /memory
/uptime, /network, /top
```

#### 🔧 Management (Değişiklik Yok)

```
/restart [service], /vpn <user>
/backup, /snapshot, /update
```

#### 🚢 CapRover (Değişiklik Yok)

```
/capbackup, /caplist, /capclean
```

#### 🛡️ Security & DDoS (Değişiklik Yok)

```
/ddos_enable, /ddos_disable, /ddos_status
/caprover_protect, /firewall
/block <ip>, /ssl <domain>
```

#### 🚨 Emergency (YENİ!)

```
/emergency_exit - Exit emergency mode
```

#### 🎉 Fun & Useful (YENİ!)

```
/joke          - Random server joke
/fortune       - Fortune cookie
/cowsay [text] - Cow says...
/funstats      - Fun statistics
/ascii         - ASCII art
/tip           - Random tip
```

---

## 📋 GÜVENLİK ÖNERİLERİ

### Temel Koruma (Herkese Önerilir)

1. **Güvenlik araçlarını kur:**

   ```bash
   bdrman → 7 → 5 (Install ALL Security Tools)
   ```

2. **Otomatik izlemeyi aktifleştir:**

   ```bash
   bdrman → 7 → 8 (Setup Advanced Monitoring)
   ```

3. **DDoS korumasını aç:**

   ```
   /ddos_enable
   ```

4. **İlk güvenlik taramasını çalıştır:**
   ```bash
   bdrman → 7 → 6 (Run Security Scan)
   ```

### İleri Seviye Koruma

5. **SSH'ı sıkılaştır:**

   ```bash
   bdrman → 7 → 1 (SSH Hardening)
   ```

6. **Otomatik güncellemeleri aktifleştir:**

   ```bash
   bdrman → 7 → 4 (Automatic Security Updates)
   ```

7. **Fail2Ban kurallarını gözden geçir:**

   ```bash
   bdrman → 7 → 2 (Fail2Ban Management)
   ```

8. **Lynis audit çalıştır:**
   ```bash
   lynis audit system
   ```

---

## 🎯 KULLANIM SENARYOLARI

### Senaryo 1: İlk Kurulum

```bash
1. bdrman → 7 → 5 (Install security tools)
2. bdrman → 7 → 8 (Setup monitoring)
3. /ddos_enable
4. /status (Kontrol)
```

### Senaryo 2: DDoS Saldırısı

```
1. Telegram'dan uyarı gelir:
   🚨 DDOS ALERT DETECTED...

2. Hemen korumayı aktifleştir:
   /caprover_protect (ACİL)

3. Durumu kontrol et:
   /ddos_status

4. Saldırgan IP'yi blokla:
   /block 1.2.3.4

5. Tam korumayı aç:
   /ddos_enable
```

### Senaryo 3: Brute Force Attempt

```
1. Telegram'dan uyarı:
   🔐 BRUTE FORCE ALERT...

2. Fail2Ban kontrolü:
   /firewall

3. Saldırgan IP blokla:
   /block 1.2.3.4

4. SSH sıkılaştır:
   bdrman → 7 → 1
```

### Senaryo 4: Disk Doldu

```
1. Telegram uyarısı:
   💾 CRITICAL DISK ALERT...

2. Durumu kontrol:
   /disk

3. Eski backupları temizle:
   /capclean

4. Detaylı bakış:
   /status
```

### Senaryo 5: Emergency Mode'dan Çıkış

```
1. Emergency mode aktif (yanlışlıkla)
2. /emergency_exit
3. /status (Doğrula)
```

---

## 🔔 TELEGRAM UYARI SİSTEMİ

### Uyarı Türleri ve Önlemler

| Uyarı            | Sebep                     | Tavsiye Edilen Aksiyon                  |
| ---------------- | ------------------------- | --------------------------------------- |
| 🚨 DDoS Alert    | Anormal bağlantı sayısı   | `/caprover_protect` → `/ddos_enable`    |
| ⚡ High CPU      | CPU %90 üstü              | `/top` → kontrol et → gerekirse restart |
| 🧠 High Memory   | RAM %90 üstü              | `/memory` → kontrol et → Docker restart |
| 💾 Disk Critical | Disk %90 dolu             | `/disk` → `/capclean` → dosya sil       |
| 🔐 Brute Force   | Çok fazla başarısız giriş | `/block <ip>` → Fail2Ban kontrol        |
| ⚙️ Service Down  | Kritik servis durdu       | `/restart <service>` → `/health`        |

---

## 📊 İZLEME VE LOG'LAR

### Sistem Logları

```bash
# Security monitor logs
tail -f /var/log/bdrman_security_alerts.log

# Fail2Ban logs
tail -f /var/log/fail2ban.log

# Audit logs
ausearch -m all

# Psad logs
tail -f /var/log/psad/psadfifo

# Lynis audit report
cat /var/log/lynis-report.dat
```

### Servis Durumları

```bash
# Security monitor
systemctl status bdrman-security-monitor

# Telegram bot
systemctl status bdrman-telegram

# Fail2Ban
fail2ban-client status

# ClamAV
systemctl status clamav-freshclam
```

---

## 🔐 GÜVENLİK TARAMASI ÇIKTISINDAKİ KAVRAMLAR

### Lynis Puanlaması

- **90-100:** Mükemmel 🟢
- **80-89:** İyi 🟡
- **70-79:** Orta 🟠
- **<70:** Zayıf 🔴

### ClamAV Tarama

- **Infected files:** Virüslü dosya sayısı
- **Scanned:** Taranan dosya sayısı
- **Known viruses:** Bilinen virüs tanımları

### RKHunter

- **Warnings:** Uyarılar (incelenmeli)
- **Suspect files:** Şüpheli dosyalar
- **Rootkits found:** Bulunan rootkit'ler (0 olmalı!)

---

## 🚀 PERFORMANS İPUÇLARI

### Güvenlik Araçları ve Performans

**Hafif Yük (<5% CPU):**

- Fail2Ban
- AppArmor
- Auditd

**Orta Yük (5-15% CPU):**

- ClamAV (daemon mode)
- Psad

**Ağır Yük (scanning sırasında):**

- ClamAV full scan (>50% CPU)
- RKHunter scan
- Lynis audit

**Öneri:** Taramaları gece veya düşük trafikli saatlerde çalıştır:

```bash
# Crontab ekle
0 3 * * * /usr/bin/clamscan -r /home
0 4 * * 0 /usr/bin/rkhunter --check
```

---

## 💾 BACKUP STRATEJİSİ

### Güvenlik Araçları ile Entegre Backup

1. **Backup öncesi:**

   ```bash
   # Sistem taraması
   bdrman → 7 → 6

   # Temiz ise backup al
   /capbackup
   ```

2. **Backup sonrası:**

   ```bash
   # Dosya integrity kaydet
   aide --update

   # Backup doğrula
   /caplist
   ```

3. **Otomatik backup schedule:**

   ```bash
   # Her gece 2'de
   0 2 * * * /usr/local/bin/bdrman --auto-backup

   # Backup sonrası tarama
   30 2 * * * /usr/bin/clamscan /root/capBackup
   ```

---

## ❓ SSS (Sık Sorulan Sorular)

**S: Güvenlik araçları çok yer kaplıyor mu?**
C: ~500MB disk alanı. Log rotation ile kontrol altında.

**S: Telegram uyarıları çok sık geliyor, nasıl ayarlarım?**
C: `/etc/bdrman/security_monitor.sh` içinde `ALERT_COOLDOWN` değerini artır.

**S: Fail2Ban bir IP'yi yanlışlıkla banladı, nasıl kaldırırım?**
C: `fail2ban-client set sshd unbanip 1.2.3.4`

**S: ClamAV taraması çok yavaş, hızlandırabilir miyim?**
C: `/etc/clamav/clamd.conf` içinde `MaxThreads` artır.

**S: Emergency mode'dan çıkamıyorum!**
C: Telegram'dan `/emergency_exit` veya Ana menü → 10 → 3

**S: DDoS koruması gerçekten işe yarıyor mu?**
C: Evet! Küçük-orta saldırılarda çok etkili. Büyük saldırılarda CloudFlare gibi harici koruma önerilir.

---

## 📞 DESTEK VE TROUBLESHOOTING

### Sorun: Security monitor çalışmıyor

```bash
# Servisi kontrol et
systemctl status bdrman-security-monitor

# Logları incele
journalctl -u bdrman-security-monitor -n 50

# Yeniden başlat
systemctl restart bdrman-security-monitor
```

### Sorun: Telegram uyarıları gelmiyor

```bash
# Config'i kontrol et
cat /etc/bdrman/telegram.conf

# Manuel test
source /etc/bdrman/telegram.conf
curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d chat_id="${CHAT_ID}" \
  -d text="Test message"
```

### Sorun: Fail2Ban IP blokluyor ama saldırı devam ediyor

```bash
# DDoS korumasını aktifleştir
/ddos_enable

# Ağır modda koruma
/caprover_protect

# Tüm bağlantıları kontrol
ss -tunap | grep ESTAB
```

---

## 🎓 ÖĞRENME KAYNAKLARI

**Güvenlik Best Practices:**

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [CIS Benchmarks](https://www.cisecurity.org/cis-benchmarks/)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)

**Araç Dokümantasyonları:**

- [Fail2Ban](https://www.fail2ban.org/wiki/index.php/Main_Page)
- [ClamAV](https://docs.clamav.net/)
- [Lynis](https://cisofy.com/lynis/)

---

## 📈 GELECEKTEKİ ÖZELLIKLER (Roadmap)

- [ ] GeoIP blocking (ülke bazlı engelleme)
- [ ] Machine learning anomaly detection
- [ ] Automated incident response playbooks
- [ ] Honeypot integration
- [ ] WAF (Web Application Firewall) rules
- [ ] Container security scanning
- [ ] Compliance reporting (PCI-DSS, HIPAA)

---

**Güncelleme:** 2024-11-07  
**Versiyon:** 3.0 (Complete Security Suite)  
**Yazar:** Burak Darende

🛡️ **Stay Safe, Stay Secure!** 🛡️
