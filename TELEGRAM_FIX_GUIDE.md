# Telegram Bot Sorun Çözüm Kılavuzu

## Sorunlar

1. ✅ `pip3: command not found` hatası **DÜZELTİLDİ**
2. ⚠️ Bot başlatılıyor ama hemen kapanıyor
3. ⚠️ `/status` komutuna cevap vermiyor

## Çözümler (Güncellenmiş Kod)

### ✅ Düzeltme 1: pip3 Kurulum Kontrolü

Kod artık pip3'ün kurulu olup olmadığını kontrol ediyor ve gerekirse otomatik kuruyor.

### 📋 Sunucuda Manuel Adımlar

Şimdi sunucuda şu adımları takip edin:

#### 1. Script'i Sunucuya Yükle

```bash
# Güncellenmiş bdrman.sh dosyasını sunucuya yükleyin
# GitHub'dan pull yapın veya dosyayı kopyalayın
cd /usr/local/bin
# Eski dosyayı yedekleyin
cp bdrman bdrman.backup.$(date +%Y%m%d)
# Yeni dosyayı kopyalayın
```

#### 2. Telegram Bot'u Kurma (Düzeltilmiş)

```bash
# bdrman'ı çalıştır
bdrman

# Menüden şunları seç:
# 11 (Telegram Bot)
# 1 (Initial Setup)
```

Bot Token ve Chat ID'yi gir.

#### 3. Dependency'leri Manuel Kontrol

```bash
# Python3'ü kontrol et
python3 --version

# pip3'ü kontrol et
pip3 --version

# Eğer pip3 yok ise:
apt update && apt install -y python3-pip

# Telegram bot kütüphanesini kur
pip3 install python-telegram-bot --upgrade
```

#### 4. Bot'u Başlat

```bash
# bdrman menüsünden:
# 11 (Telegram Bot)
# 2 (Start Interactive Bot Server)
```

#### 5. Durumu Kontrol Et

```bash
# Servis durumunu kontrol et
systemctl status bdrman-telegram

# Logları canlı izle
journalctl -u bdrman-telegram -f

# Eğer hata varsa logları göster
journalctl -u bdrman-telegram -n 100 --no-pager
```

#### 6. Bot Test Et

Telegram'dan botunuza şu komutları gönderin:

```
/start
/help
/status
```

## Yaygın Hatalar ve Çözümleri

### Hata: "pip3: command not found"

**Çözüm:**

```bash
apt update
apt install -y python3-pip
```

### Hata: "ModuleNotFoundError: No module named 'telegram'"

**Çözüm:**

```bash
pip3 install python-telegram-bot --upgrade
```

### Hata: Bot başlıyor ama hemen duruyor

**Çözüm:**

```bash
# Logları kontrol et
journalctl -u bdrman-telegram -n 50

# Muhtemelen şu hatalardan biri:
# 1. Token yanlış - /etc/bdrman/telegram.conf'u kontrol et
# 2. Network sorunu - interneti kontrol et
# 3. Python hatası - logları kontrol et

# Manuel test:
cd /etc/bdrman
python3 telegram_bot.py
# Ctrl+C ile durdur
```

### Hata: Bot cevap vermiyor

**Kontrol listesi:**

1. ✅ Bot Token doğru mu? (@BotFather'dan kontrol et)
2. ✅ Chat ID doğru mu? (@userinfobot ile kontrol et)
3. ✅ Bot çalışıyor mu? (`systemctl status bdrman-telegram`)
4. ✅ Internet bağlantısı var mı? (`ping google.com`)
5. ✅ Firewall'dan geçiyor mu? (Port 443 açık olmalı)

**Test:**

```bash
# Config'i kontrol et
cat /etc/bdrman/telegram.conf

# Bot'u manuel başlat (debug için)
systemctl stop bdrman-telegram
cd /etc/bdrman
python3 telegram_bot.py

# Şimdi Telegram'dan /status gönder
# Terminalde ne görüyorsun?
```

## Doğru Kurulum Sırası

1. ✅ Python3 kur: `apt install python3 python3-pip -y`
2. ✅ Telegram kütüphanesi: `pip3 install python-telegram-bot`
3. ✅ bdrman ile setup: Menü → 11 → 1
4. ✅ Bot'u başlat: Menü → 11 → 2
5. ✅ Durumu kontrol: `systemctl status bdrman-telegram`
6. ✅ Logları izle: `journalctl -u bdrman-telegram -f`
7. ✅ Test et: Telegram'dan `/start`

## Debug Komutları

```bash
# Bot config'ini göster
cat /etc/bdrman/telegram.conf

# Bot script'ini kontrol et
ls -la /etc/bdrman/telegram_bot.py

# Bot'u manuel çalıştır (debug mode)
cd /etc/bdrman
python3 telegram_bot.py

# Servis logları (son 100 satır)
journalctl -u bdrman-telegram -n 100 --no-pager

# Servis logları (canlı)
journalctl -u bdrman-telegram -f

# Python ve pip versiyonları
python3 --version
pip3 --version

# Telegram kütüphanesi kurulu mu?
python3 -c "import telegram; print(telegram.__version__)"

# Servis dosyasını kontrol et
cat /etc/systemd/system/bdrman-telegram.service

# Servisi yeniden yükle
systemctl daemon-reload
systemctl restart bdrman-telegram
```

## Sonraki Adımlar

Eğer yukarıdaki adımları takip ettikten sonra hala sorun varsa:

1. **Log çıktısını paylaş:**

```bash
journalctl -u bdrman-telegram -n 100 --no-pager > telegram-bot-logs.txt
cat telegram-bot-logs.txt
```

2. **Manuel test yap:**

```bash
systemctl stop bdrman-telegram
cd /etc/bdrman
python3 telegram_bot.py
# Terminalde ne hatası veriyor?
```

3. **Config'i kontrol et:**

```bash
cat /etc/bdrman/telegram.conf
# Token ve Chat ID doğru görünüyor mu?
```
