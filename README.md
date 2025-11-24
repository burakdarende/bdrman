# BDRman v4.0

**BDRman** - Kapsamlı Linux Sunucu Yönetim Aracı

## 🚀 Yeni Özellikler (v4.0)

### CLI Komutları
Artık terminal üzerinden hızlı komutlar çalıştırabilirsiniz:

```bash
bdrman status                    # Hızlı sistem durumu
bdrman backup create             # Yedekleme oluştur
bdrman backup list               # Yedeklemeleri listele
bdrman telegram send "mesaj"     # Telegram mesajı gönder
bdrman docker ps                 # Container listesi
bdrman docker logs <container>   # Container logları
bdrman docker restart <container># Container yeniden başlat
bdrman vpn add <kullanıcı>       # VPN kullanıcısı ekle
bdrman vpn list                  # VPN kullanıcılarını listele
bdrman update                    # BDRman'i güncelle
```

### Renkli Terminal Çıktısı
- ✅ Başarı mesajları (yeşil)
- ❌ Hata mesajları (kırmızı)
- ⚠️  Uyarı mesajları (sarı)
- ℹ️  Bilgi mesajları (mavi)
- Progress bar'lar
- Tablo formatında çıktılar

## 📋 Özellikler

### Temel Yönetim
- **VPN (WireGuard):** Kullanıcı ekleme, durum kontrolü
- **CapRover:** Yedekleme, geri yükleme, temizleme
- **Güvenlik Duvarı (UFW):** Port yönetimi, IP engelleme
- **Yedekleme:** Otomatik/manuel yedekleme, geri yükleme
- **İzleme:** CPU, RAM, Disk, Network
- **Telegram Bot:** Uzaktan yönetim, uyarılar

### Gelişmiş Özellikler
- **Docker Yönetimi:** Container ve image yönetimi (CLI)
- **Güvenlik Sertleştirme:** SSH, Fail2Ban, SSL
- **Olay Müdahalesi:** Acil durum modu, hızlı geri alma
- **Konfigürasyon Yönetimi:** Export/import
- **Otomatik Güncelleme:** GitHub'dan versiyon kontrolü

### Güvenlik (Pasif - Manuel Aktifleştirme)
- **2FA:** İki faktörlü kimlik doğrulama (kapalı)
  - Kurulum: `bdrman` menüden Security → 2FA Setup
  - Aktifleştirme: `2FA_ENABLED=true` in config
- **Audit Log:** Tüm işlemleri kaydetme (kapalı)
  - Aktifleştirme: `AUDIT_LOG_ENABLED=true` in config
  - Görüntüleme: `audit_log_view` fonksiyonu
- **Güvenlik Taraması:** Port ve zayıf şifre kontrolü (manuel)
  - Çalıştırma: Menüden veya `security_scan` fonksiyonu

### Modüler Mimari (v4.0)
- **Hafif ve Hızlı:** Web arayüzü tamamen kaldırılarak sistem kaynakları optimize edildi.
- **CLI Odaklı:** Tüm işlemler terminal üzerinden hızlıca yapılabilir.
- **Telegram Entegrasyonu:** Sunucu yönetimi artık cebinizde.

### Telegram Bot (Gelişmiş)
- **İzleme:** Sistem durumu, Docker, Servisler
- **Yönetim:** VPN, Yedekleme, Güncelleme
- **Güvenlik:** Panic Mode, Firewall, IP Bloklama
- **Acil Durum:** PIN korumalı kritik işlemler

## 📦 Kurulum

### Otomatik Kurulum (Önerilen)
```bash
curl -s https://raw.githubusercontent.com/burakdarende/bdrman/main/install.sh | bash
```

### Manuel Kurulum
```bash
wget https://raw.githubusercontent.com/burakdarende/bdrman/main/bdrman.sh
sudo mv bdrman.sh /usr/local/bin/bdrman
sudo chmod +x /usr/local/bin/bdrman
sudo bdrman
```

## 🎯 Hızlı Başlangıç

1. **İlk Kurulum:**
   ```bash
   sudo bdrman
   ```

2. **Telegram Bot Kurulumu:**
   - Menüden `11) Telegram Bot` → `1) Initial Setup`
   - Bot token ve Chat ID girin

3. **Hızlı Komutlar:**
   ```bash
   bdrman status              # Sistem durumu
   bdrman backup create       # Yedekleme al
   bdrman docker ps           # Containerları listele
   ```

## 📖 Kullanım Örnekleri

### Sistem Durumu
```bash
$ bdrman status
ℹ System Status

Metric              Value
-------------------- --------------------
Hostname            motion-server
Uptime              up 5 days, 3 hours
CPU Load            0.45, 0.52, 0.48
Memory              2.1G/8.0G
Disk                45G/100G (45%)

✓ Status check complete
```

### Yedekleme
```bash
$ bdrman backup create
ℹ Creating backup...
✓ Backup created: /var/backups/bdrman/backup_20251122_123456.tar.gz
```

### Docker Yönetimi
```bash
$ bdrman docker ps
ℹ Docker Containers
NAMES               STATUS              PORTS
captain-captain     Up 5 days           80/tcp, 443/tcp
nginx-proxy         Up 5 days           80/tcp
```

## 🔧 Konfigürasyon

Konfigürasyon dosyası: `/etc/bdrman/config.conf`

Örnek ayarlar:
```bash
# İzleme eşikleri
CPU_ALERT_THRESHOLD=90
MEMORY_ALERT_THRESHOLD=90
DISK_ALERT_THRESHOLD=90

# Yedekleme
BACKUP_RETENTION_DAYS=7

# Güvenlik (Pasif - Manuel Aktifleştirme)
2FA_ENABLED=false
AUDIT_LOG_ENABLED=false
```

## 🔐 Güvenlik Özellikleri

### Aktif Güvenlik
- PIN korumalı kritik Telegram komutları
- Güvenli yedekleme (atomic write)
- SSH sertleştirme
- Fail2Ban entegrasyonu
- SSL sertifika yönetimi

### Pasif Güvenlik (Manuel Aktifleştirme Gerekli)
- 2FA: `bdrman 2fa enable`
- Audit Log: `bdrman audit enable`
- Güvenlik Taraması: `bdrman security scan`

## 📊 Telegram Bot Komutları

- `/start` - Bot bilgisi
- `/help` - Komut listesi
- `/status` - Sistem durumu
- `/vpn <kullanıcı>` - VPN kullanıcısı ekle
- `/backup` - Yedekleme oluştur
- `/snapshot` - Sistem snapshot (PIN gerekli)
- `/emergency_exit` - Acil durum modundan çık (PIN gerekli)

## 🗑️ Kaldırma

```bash
sudo bdrman
# Advanced Tools (9) → Uninstall BDRman (8)
```

Veya manuel:
```bash
sudo rm /usr/local/bin/bdrman
sudo rm -rf /etc/bdrman
```

## 📝 Changelog

### v4.0 (2025-11-22)
- ✨ CLI komutları eklendi
- 🎨 Renkli terminal çıktısı
- 🐳 Docker yönetimi (CLI)
- 🔄 Otomatik güncelleme komutu
- 📊 Tablo formatında çıktılar
- 🎯 Progress bar desteği

### v3.3 (2025-11-22)
- 🔒 Güvenlik iyileştirmeleri
- 📱 Telegram bot PIN koruması
- 🗑️ Kaldırma özelliği
- 🔧 İzin düzeltme aracı

## 🤝 Katkıda Bulunma

Katkılarınızı bekliyoruz! Pull request göndermekten çekinmeyin.

## 📄 Lisans

MIT License - Detaylar için LICENSE dosyasına bakın.

## 👤 Yazar

**Burak Darende**
- GitHub: [@burakdarende](https://github.com/burakdarende)

## 🙏 Teşekkürler

Bu projeyi kullandığınız için teşekkürler! Sorularınız için issue açabilirsiniz.
