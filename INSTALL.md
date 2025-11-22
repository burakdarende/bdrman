# BDRman Kurulum Rehberi

## 1. Otomatik Kurulum (Önerilen) ⚡

**Tek komutla tam kurulum!** Python, bağımlılıklar, web dashboard - her şey otomatik:

```bash
curl -s https://raw.githubusercontent.com/burakdarende/bdrman/main/install.sh | bash
```

**Kurulacaklar:**
- ✅ Python3 ve pip
- ✅ Gerekli bağımlılıklar (curl, wget, tar, rsync)
- ✅ Opsiyonel paketler (docker, jq, sqlite3)
- ✅ Ana script (`/usr/local/bin/bdrman`)
- ✅ Web dashboard (`/opt/bdrman/`)
- ✅ Flask (Python venv içinde)
- ✅ Gerekli dizinler ve izinler

**Kurulum sonrası:**
```bash
bdrman              # Interactive menu
bdrman status       # Quick status
bdrman web start    # Start web dashboard
```

## 2. Manuel Kurulum

Eğer otomatik kurulumu kullanmak istemezseniz:

```bash
# 1. Python3 kurulumu
apt install python3 python3-pip python3-venv

# 2. Ana scripti indirin
wget https://raw.githubusercontent.com/burakdarende/bdrman/main/bdrman.sh
sudo mv bdrman.sh /usr/local/bin/bdrman
sudo chmod +x /usr/local/bin/bdrman

# 3. Web dashboard'u indirin
sudo mkdir -p /opt/bdrman
sudo wget https://raw.githubusercontent.com/burakdarende/bdrman/main/web_dashboard.py -O /opt/bdrman/web_dashboard.py
sudo chmod +x /opt/bdrman/web_dashboard.py

# 4. Web dashboard'u kurun
sudo bdrman web setup

# 5. Çalıştırın!
sudo bdrman
```

## 3. Sistem Gereksinimleri

**Minimum:**
- Ubuntu 18.04+ / Debian 10+ / CentOS 7+
- 512MB RAM
- 1GB disk alanı

**Önerilen:**
- Ubuntu 20.04+ / Debian 11+
- 1GB+ RAM
- 5GB+ disk alanı
- Docker (opsiyonel)

## 4. Kurulum Sonrası

```bash
# Web dashboard'u başlat
bdrman web start

# Tarayıcıda aç
http://sunucu-ip:8443

# Telegram bot kurulumu
bdrman
# Menüden: 11) Telegram Bot → 1) Initial Setup
```

## 5. Sorun Giderme

**Python bulunamadı:**
```bash
apt install python3 python3-pip python3-venv
```

**Flask kurulum hatası:**
```bash
bdrman web setup
```

**İzin hatası:**
```bash
sudo bdrman
```
