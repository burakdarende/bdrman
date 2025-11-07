# 🚀 BDRman Sunucu Deployment Rehberi

## 📦 Dosya Listesi (Yüklenecekler)

```
✅ bdrman.sh              → Ana script
✅ config.conf.example    → Konfigürasyon şablonu
✅ logrotate.bdrman       → Log rotation ayarları
✅ validate.sh            → Test script'i
✅ deploy.sh              → Otomatik deployment script'i

❌ README.md              → Yükleme (sadece GitHub için)
❌ CHANGELOG.md           → Yükleme (sadece GitHub için)
❌ SECURITY_FEATURES_V3.md → Yükleme (sadece GitHub için)
❌ TELEGRAM_*.md          → Yükleme (sadece GitHub için)
```

---

## 🎯 Yöntem 1: Otomatik Deployment (ÖNERİLEN)

### Adım 1: Dosyaları sunucuya yükle

```bash
# Lokal bilgisayardan (Windows/PowerShell):
scp bdrman.sh config.conf.example logrotate.bdrman validate.sh deploy.sh root@SUNUCU_IP:/root/

# VEYA FileZilla/WinSCP ile:
# /root/ klasörüne 5 dosyayı sürükle-bırak
```

### Adım 2: Deployment script'i çalıştır

```bash
# Sunucuda:
ssh root@SUNUCU_IP

cd /root
chmod +x deploy.sh
sudo bash deploy.sh
```

**Deploy script otomatik yapar:**

- ✅ bdrman.sh → /usr/local/bin/bdrman
- ✅ config.conf.example → /etc/bdrman/config.conf
- ✅ logrotate.bdrman → /etc/logrotate.d/bdrman
- ✅ validate.sh → /usr/local/bin/bdrman-validate
- ✅ Tüm izinleri ayarlar (chmod, chown)
- ✅ Gerekli klasörleri oluşturur

### Adım 3: Test et

```bash
sudo bdrman-validate  # Tüm testleri çalıştır
sudo bdrman --version # v3.1 görmeli
```

---

## 🛠️ Yöntem 2: Manuel Deployment

### Adım 1: Ana script'i kur

```bash
sudo cp bdrman.sh /usr/local/bin/bdrman
sudo chmod 755 /usr/local/bin/bdrman
sudo chown root:root /usr/local/bin/bdrman
```

### Adım 2: Konfigürasyonu kur

```bash
sudo mkdir -p /etc/bdrman
sudo cp config.conf.example /etc/bdrman/config.conf
sudo chmod 600 /etc/bdrman/config.conf
sudo chown root:root /etc/bdrman/config.conf
```

### Adım 3: Logrotate'i kur

```bash
sudo cp logrotate.bdrman /etc/logrotate.d/bdrman
sudo chmod 644 /etc/logrotate.d/bdrman
sudo chown root:root /etc/logrotate.d/bdrman
```

### Adım 4: Validation script'i kur (opsiyonel)

```bash
sudo cp validate.sh /usr/local/bin/bdrman-validate
sudo chmod 755 /usr/local/bin/bdrman-validate
sudo chown root:root /usr/local/bin/bdrman-validate
```

### Adım 5: Test et

```bash
sudo bdrman --version
```

---

## 📁 Sonuç: Sunucudaki Dosya Yapısı

```
/usr/local/bin/
├── bdrman                    (755, root:root) ← Ana script
└── bdrman-validate           (755, root:root) ← Test script

/etc/bdrman/
├── config.conf               (600, root:root) ← Yapılandırma
├── telegram.conf             (600, root:root) ← Telegram (runtime'da oluşur)
└── security_monitor.sh       (755, root:root) ← Monitor (runtime'da oluşur)

/etc/logrotate.d/
└── bdrman                    (644, root:root) ← Log rotation

/var/log/
├── bdrman.log                (640, root:root) ← Ana log
└── bdrman_security_alerts.log (640, root:root) ← Güvenlik logları

/var/backups/bdrman/          (755, root:root) ← Backup klasörü
/var/lock/
└── bdrman.lock               (644, root:root) ← Lock file (runtime)
```

---

## ⚙️ İlk Kurulum Sonrası Yapılacaklar

### 1. Konfigürasyonu Özelleştir (Opsiyonel)

```bash
sudo nano /etc/bdrman/config.conf

# Önemli ayarlar:
MONITORING_INTERVAL=30        # Monitoring sıklığı (saniye)
ALERT_COOLDOWN=300           # Alert spam önleme (saniye)
DDOS_THRESHOLD=50            # DDoS eşiği (bağlantı/IP)
BACKUP_RETENTION_DAYS=7      # Yedekleme saklama süresi
```

### 2. Telegram Bot Kur (Önerilen)

```bash
sudo bdrman
→ 11) Telegram Bot
→ 1) Setup Telegram

# Bot token al: https://t.me/BotFather
# Chat ID al: https://t.me/userinfobot
```

### 3. Güvenlik Monitoring Aktifleştir (Önerilen)

```bash
sudo bdrman
→ 7) Security & Hardening
→ 8) Setup Advanced Monitoring

# Bu otomatik yapar:
# - security_monitor.sh oluşturur
# - systemd service başlatır
# - Real-time tehdit tespiti aktif olur
```

### 4. Güvenlik Araçlarını Kur (Önerilen)

```bash
sudo bdrman
→ 7) Security & Hardening
→ 5) Install Security Tools (All)

# Kurulacaklar:
# - Fail2Ban (brute force koruması)
# - ClamAV (antivirüs)
# - RKHunter (rootkit tespiti)
# - Lynis (güvenlik audit)
# - AppArmor, Aide, Auditd, Psad
```

---

## 🧪 Test & Doğrulama

### Hızlı Test

```bash
# Komut çalışıyor mu?
bdrman --version

# Dependency kontrolü
bdrman --check-deps

# Tam test suite
sudo bdrman-validate
```

### Manuel Test

```bash
# Ana menü
sudo bdrman

# Otomatik backup
sudo bdrman --auto-backup

# Telegram test
sudo bdrman-telegram "Test mesajı"

# Monitoring servis durumu
sudo systemctl status bdrman-security-monitor
```

---

## 🔧 Güncelleme (v3.0 → v3.1)

Eğer eski versiyonu kuruluysa:

```bash
# 1. Yeni dosyaları yükle
scp bdrman.sh root@SUNUCU_IP:/root/

# 2. Sunucuda deployment yap
ssh root@SUNUCU_IP
cd /root
sudo bash deploy.sh

# 3. Monitoring'i yeniden başlat
sudo systemctl restart bdrman-security-monitor

# 4. Test et
sudo bdrman-validate
```

---

## ❓ Sık Sorulan Sorular

### Q: .md dosyalarını yüklemeli miyim?

**A:** HAYIR. README.md, CHANGELOG.md vb. sadece GitHub için. Sunucuya yükleme.

### Q: deploy.sh'den sonra dosyaları silebilir miyim?

**A:** EVET. /root/ altındaki dosyalar sadece kurulum için. Deploy sonrası silebilirsin:

```bash
rm /root/bdrman.sh /root/config.conf.example /root/logrotate.bdrman /root/validate.sh /root/deploy.sh
```

### Q: Config'i sonradan değiştirebilir miyim?

**A:** EVET. İstediğin zaman:

```bash
sudo nano /etc/bdrman/config.conf
# Değişiklik yap, kaydet
# Monitoring varsa restart et:
sudo systemctl restart bdrman-security-monitor
```

### Q: Birden fazla sunucuya kurulum?

**A:** Her sunucuda deployment script'i çalıştır:

```bash
for server in server1 server2 server3; do
  scp deploy.sh bdrman.sh config.conf.example logrotate.bdrman validate.sh root@$server:/root/
  ssh root@$server "cd /root && chmod +x deploy.sh && bash deploy.sh"
done
```

---

## 🆘 Sorun Giderme

### Script çalışmıyor (bash\r hatası)

```bash
# Line endings düzelt:
sudo sed -i 's/\r$//' /usr/local/bin/bdrman
sudo sed -i 's/\r$//' /usr/local/bin/bdrman-validate
```

### Telegram çalışmıyor

```bash
# Config izinlerini kontrol et:
ls -la /etc/bdrman/telegram.conf
# Çıktı: -rw------- 1 root root

# Düzelt:
sudo chmod 600 /etc/bdrman/telegram.conf
sudo chown root:root /etc/bdrman/telegram.conf
```

### Lock dosyası hatası

```bash
# Stale lock varsa sil:
sudo rm /var/lock/bdrman.lock
```

---

## 📞 Yardım

- **GitHub Issues**: https://github.com/burakdarende/bdrman/issues
- **Telegram Test**: `sudo bdrman-telegram "Yardım!"`
- **Logs**: `sudo tail -f /var/log/bdrman.log`

---

**Son Güncelleme**: 2025-11-07  
**Versiyon**: 3.1  
**Deployment Süresi**: ~2 dakika (otomatik)
