# BDRman Kurulum Rehberi

BDRman, tek bir dosya (`bdrman.sh`) olarak çalışacak şekilde tasarlanmıştır.

## Kurulum

**Not:** Repo şu anda private durumda. Public yapmanız önerilir.

### Yöntem 1: Manuel Kurulum (Önerilen)

```bash
# 1. Dosyayı indirin (GitHub'dan raw olarak)
wget https://raw.githubusercontent.com/burakdarende/bdrman/main/bdrman.sh

# 2. Çalıştırma izni verin ve sistem yoluna taşıyın
sudo mv bdrman.sh /usr/local/bin/bdrman
sudo chmod +x /usr/local/bin/bdrman

# 3. Çalıştırın!
sudo bdrman
```

### Yöntem 2: Otomatik Kurulum (Repo Public Olduktan Sonra)

Repoyu public yaptıktan sonra:

```bash
curl -s https://raw.githubusercontent.com/burakdarende/bdrman/main/install.sh | bash
```

Artık terminalde sadece `bdrman` yazarak programa erişebilirsiniz.

## 2. Opsiyonel Dosyalar

Klasördeki diğer dosyalar zorunlu değildir ancak faydalıdır:

*   **`logrotate.bdrman`**: Log dosyalarının şişmesini engeller. `/etc/logrotate.d/bdrman` konumuna kopyalayabilirsiniz.
*   **`config.conf.example`**: Örnek ayar dosyasıdır. İncelemek için tutabilirsiniz.

*Diğer tüm gereksiz dosyalar (lib, deploy.sh, validate.sh) temizlenmiştir.*
