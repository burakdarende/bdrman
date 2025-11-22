# BDRman Kurulum Rehberi

BDRman, tek bir dosya (`bdrman.sh`) olarak çalışacak şekilde tasarlanmıştır.

## 1. Otomatik Kurulum (Önerilen)

Aşağıdaki komutu sunucunuzda çalıştırmanız yeterlidir. Bu komut hem ana scripti hem de web dashboard'u indirir.

```bash
curl -s https://raw.githubusercontent.com/burakdarende/bdrman/main/install.sh | bash
```

**Kurulacak dosyalar:**
- `/usr/local/bin/bdrman` - Ana script
- `/opt/bdrman/web_dashboard.py` - Web arayüzü (opsiyonel)

## 2. Manuel Kurulum

Eğer otomatik kurulumu kullanmak istemezseniz:

```bash
# 1. Ana scripti indirin
wget https://raw.githubusercontent.com/burakdarende/bdrman/main/bdrman.sh

# 2. Çalıştırma izni verin ve sistem yoluna taşıyın
sudo mv bdrman.sh /usr/local/bin/bdrman
sudo chmod +x /usr/local/bin/bdrman

# 3. (Opsiyonel) Web dashboard'u indirin
sudo mkdir -p /opt/bdrman
sudo wget https://raw.githubusercontent.com/burakdarende/bdrman/main/web_dashboard.py -O /opt/bdrman/web_dashboard.py
sudo chmod +x /opt/bdrman/web_dashboard.py

# 4. Çalıştırın!
sudo bdrman
```

## 3. Web Dashboard Kullanımı

Web dashboard'u başlatmak için:

```bash
# Python ve Flask gerekli
apt install python3 python3-pip
pip3 install flask

# Dashboard'u başlat
python3 /opt/bdrman/web_dashboard.py
```

Tarayıcıda: `http://sunucu-ip:8443`

## 4. Opsiyonel Dosyalar

Klasördeki diğer dosyalar zorunlu değildir ancak faydalıdır:

- **`logrotate.bdrman`**: Log dosyalarının şişmesini engeller. `/etc/logrotate.d/bdrman` konumuna kopyalayabilirsiniz.
- **`config.conf.example`**: Örnek ayar dosyasıdır. İncelemek için tutabilirsiniz.
