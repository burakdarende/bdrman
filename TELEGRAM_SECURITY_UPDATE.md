# 🔒 Telegram Bot Güvenlik Güncellemesi v2.1

## ✅ Yapılan Değişiklikler

### 🚫 Kaldırılan Tehlikeli Komutlar

#### 1. `/exec` - Tamamen Kaldırıldı ❌

**Neden:** Sunucuda herhangi bir komut çalıştırabiliyordu
**Risk:** Bypass edilebilir, çok tehlikeli
**Alternatif:** Ana menüyü kullan

#### 2. `/emergency` - Tamamen Kaldırıldı ❌

**Neden:** Tüm servisleri durdurup firewall değiştiriyordu
**Risk:** Yanlışlıkla aktive edilirse servisler kapanır
**Alternatif:** Manuel kontrol daha güvenli

#### 3. `/caprestore` - Tamamen Kaldırıldı ❌

**Neden:** CapRover volume restore ediyordu
**Risk:** Yanlış backup seçilirse VERİ KAYBI
**Alternatif:** Ana menüden dikkatli restore

---

## 🆕 Eklenen Yeni Özellikler

### 🛡️ DDoS Koruması Komutları (YENİ!)

#### `/ddos_enable` - DDoS Korumasını Aktifleştir

**Ne yapar:**

- SYN flood koruması (1 req/sec)
- ICMP flood koruması (1 ping/sec)
- Port scanning koruması
- Bağlantı limiti (HTTP/HTTPS için 20 per IP)
- Rate limiting (10 req/sec per IP)

**Örnek kullanım:**

```
/ddos_enable
```

**Çıktı:**

```
✅ DDoS Protection Enabled!

Applied protections:
• SYN flood protection (1 req/sec)
• ICMP flood protection (1 ping/sec)
• Port scanning protection
• Connection limit (20 per IP for HTTP/HTTPS)
• Rate limiting (10 req/sec per IP)

CapRover Apps Protected:
• Port 80 (HTTP)
• Port 443 (HTTPS)
```

#### `/ddos_disable` - DDoS Korumasını Kapat

**Ne yapar:** Tüm DDoS koruma kurallarını kaldırır

**Örnek kullanım:**

```
/ddos_disable
```

#### `/ddos_status` - DDoS Koruma Durumunu Kontrol Et

**Ne yapar:**

- Aktif koruma kurallarını gösterir
- Mevcut bağlantı sayılarını gösterir
- En çok bağlanan IP'leri listeler

**Örnek kullanım:**

```
/ddos_status
```

**Çıktı:**

```
🛡️ DDoS Protection Status
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Protection Status: 🟢 Active

Active Rules:
• SYN Flood Protection: ✅
• ICMP Flood Protection: ✅
• Port Scan Protection: ✅
• Connection Limiting: ✅

Current Connections:
• Total: 45
• HTTP (80): 12
• HTTPS (443): 28

Top IPs Connected:
  15 192.168.1.100
   8 192.168.1.101
   5 192.168.1.102
```

#### `/caprover_protect` - ⚡ Hızlı CapRover Koruması (ACİL DURUM)

**Ne yapar:**

- CapRover portlarına özel koruma
- Port 3000 (Dashboard): Max 10 bağlantı/IP
- Port 80: Max 30 bağlantı/IP
- Port 443: Max 30 bağlantı/IP
- Rate limit: 5 req/sec per IP
- CapRover Nginx'i restart eder

**Ne zaman kullan:** DDoS saldırısı şüphesi olduğunda!

**Örnek kullanım:**

```
/caprover_protect
```

---

## ⬆️ İyileştirilen Komutlar

### `/status` - Çok Daha Detaylı! 📊

**Eskiden:**

- Basit disk, memory bilgisi
- 3-4 servis durumu
- Docker container sayısı

**Şimdi:**

- ✅ Detaylı disk bilgisi (used/free/total)
- ✅ Detaylı memory bilgisi (percentage)
- ✅ CPU kullanımı ve çekirdek sayısı
- ✅ Network bilgisi (IP, bağlantı sayısı)
- ✅ CapRover özel durum bilgisi
- ✅ Güvenlik bilgisi (firewall, failed logins)
- ✅ Renkli ikonlar (🟢🟡🔴)
- ✅ Timestamp

**Örnek çıktı:**

```
📊 DETAILED SYSTEM STATUS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🖥️ Server Information
• Hostname: my-server
• Kernel: 5.15.0-94-generic
• Uptime: 12 days
• Started: 2024-10-26 10:30:00

💻 System Resources
🟢 Disk: 45% (180G used / 220G free)
   Total: 400G

🟢 Memory: 62% (4.8G / 8G)
   Free: 3.2G

⚡ CPU: 23% usage
   Cores: 4
   Load Average: 0.45, 0.52, 0.48

🐳 Docker Containers
• Running: 12
• Stopped: 3
• Total: 15

🚢 CapRover Status
• Status: ✅ Running
• Apps: 8

🌐 Network
• IP Address: 192.168.1.100
• Active Connections: 45

⚙️ Services
✅ docker
✅ nginx
⚠️ wg-quick@wg0
✅ ufw
✅ ssh

🔒 Security
• Firewall: Status: active
• Recent Failed Logins: 2

━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📅 Generated: 2024-11-07 14:30:25
```

---

## 📋 Güncel Komut Listesi

### ✅ Güvenli Komutlar (Sadece Okuma)

```
/status          - Detaylı sistem durumu (YENİ: ÇOK DETAYLI!)
/health          - Sağlık kontrolü
/docker          - Docker durumu
/containers      - Container listesi
/services        - Servis durumu
/logs            - Son hatalar
/disk            - Disk kullanımı
/memory          - Bellek kullanımı
/uptime          - Uptime bilgisi
/network         - Network bilgisi
/top             - En çok kaynak kullanan süreçler
/firewall        - Firewall durumu
/caplist         - Backup geçmişi
```

### ⚠️ Yazma İzinli Komutlar (Orta Risk)

```
/vpn <user>      - VPN kullanıcısı oluştur
/restart <svc>   - Servis restart
/backup          - Sistem backup
/snapshot        - Sistem snapshot
/capbackup       - CapRover backup
/capclean        - Eski backup temizle
/block <ip>      - IP blokla
/ssl <domain>    - SSL al
/update          - Sistem güncellemesi
```

### 🛡️ YENİ: DDoS Koruması

```
/ddos_enable         - DDoS korumasını aç
/ddos_disable        - DDoS korumasını kapat
/ddos_status         - Koruma durumunu kontrol et
/caprover_protect    - ⚡ Acil CapRover koruması
```

### 🚫 KALDIRILDI (Güvenlik)

```
/exec            ❌ KALDIRILDI - Çok tehlikeli
/emergency       ❌ KALDIRILDI - Risk oluşturuyor
/caprestore      ❌ KALDIRILDI - Veri kaybı riski
```

---

## 🚀 Güncellemeyi Uygulama

### 1. Sunucuda Bot'u Durdur

```bash
systemctl stop bdrman-telegram
```

### 2. Yeni bdrman.sh'ı Yükle

```bash
cd /usr/local/bin
cp bdrman bdrman.backup.$(date +%Y%m%d)
# Yeni dosyayı buraya kopyala
chmod +x bdrman
```

### 3. Bot'u Yeniden Başlat

```bash
# Ana menüden
bdrman
# 11 → 7 (Restart Bot Server)
```

### 4. Test Et

Telegram'dan:

```
/help
/status
/ddos_status
```

---

## 📊 Güvenlik Karşılaştırması

| Özellik           | Önceki v2.0        | Yeni v2.1              |
| ----------------- | ------------------ | ---------------------- |
| `/exec` komutu    | ✅ Var (TEHLİKELİ) | ❌ Kaldırıldı          |
| `/emergency`      | ✅ Var (RİSKLİ)    | ❌ Kaldırıldı          |
| `/caprestore`     | ✅ Var (RİSKLİ)    | ❌ Kaldırıldı          |
| DDoS Koruması     | ❌ Yok             | ✅ Var (4 komut)       |
| `/status` detayı  | ⭐⭐ Basit         | ⭐⭐⭐⭐⭐ Çok detaylı |
| Güvenlik seviyesi | 🟡 Orta            | 🟢 Yüksek              |

---

## 🎯 Kullanım Senaryoları

### Senaryo 1: DDoS Saldırısı Şüphesi

```
1. /ddos_status           # Durumu kontrol et
2. /caprover_protect      # Acil CapRover koruması
3. /status                # Sistem durumunu kontrol et
4. /ddos_enable           # Tam korumayı aktifleştir
```

### Senaryo 2: Rutin Kontrol

```
1. /status                # Detaylı durum
2. /health                # Sağlık kontrolü
3. /docker                # Container durumu
4. /ddos_status           # Koruma aktif mi?
```

### Senaryo 3: Backup Sonrası

```
1. /capbackup             # Backup oluştur
2. /caplist               # Backup doğrula
3. /status                # Disk doluluk kontrol
```

---

## ⚡ Hızlı Referans

### Acil Durumda:

```
/caprover_protect    # CapRover'ı hemen koru
/ddos_enable         # Tam DDoS koruması
/block 1.2.3.4       # Şüpheli IP'yi blokla
```

### Günlük Kullanım:

```
/status              # Sabah kontrol
/health              # Sağlık durumu
/logs                # Sorun var mı?
```

### Bakım:

```
/capbackup           # Haftalık backup
/capclean            # Aylık temizlik
/update              # Güvenlik güncellemeleri
```

---

## 🔐 Güvenlik Notları

1. ✅ Bot sadece kayıtlı Chat ID'den komut alır
2. ✅ Tehlikeli komutlar tamamen kaldırıldı
3. ✅ Restore işlemi için ana menü kullanılmalı
4. ✅ DDoS koruması otomatik log tutar
5. ✅ Tüm kritik işlemler `/var/log/bdrman.log`'a yazılır

---

## 📞 Destek

Sorun yaşarsan:

```bash
# Bot loglarına bak
journalctl -u bdrman-telegram -n 50

# Manuel test
systemctl stop bdrman-telegram
cd /etc/bdrman
python3 telegram_bot.py
```

---

**Güncelleme:** 2024-11-07  
**Versiyon:** 2.1 (Security Enhanced)  
**Yazar:** Burak Darende
