# BDRman Kurulum Rehberi

BDRman, tek bir dosya (`bdrman.sh`) olarak çalışacak şekilde tasarlanmıştır.

## 1. Hızlı Kurulum

Sadece `bdrman.sh` dosyasını sunucunuza atmanız yeterlidir.

```bash
# 1. Dosyayı indirin (veya kopyalayın)
wget https://raw.githubusercontent.com/burakdarende/bdrman/main/bdrman.sh

# 2. Çalıştırma izni verin ve sistem yoluna taşıyın
sudo mv bdrman.sh /usr/local/bin/bdrman
sudo chmod +x /usr/local/bin/bdrman

# 3. Çalıştırın!
sudo bdrman
```

## 2. Opsiyonel Dosyalar

Klasördeki diğer dosyalar zorunlu değildir ancak faydalıdır:

*   **`logrotate.bdrman`**: Log dosyalarının şişmesini engeller. `/etc/logrotate.d/bdrman` konumuna kopyalayabilirsiniz.
*   **`config.conf.example`**: Örnek ayar dosyasıdır. İncelemek için tutabilirsiniz.

*Diğer tüm gereksiz dosyalar (lib, deploy.sh, validate.sh) temizlenmiştir.*
