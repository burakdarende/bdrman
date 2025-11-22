# BDRman Kurulum Rehberi

BDRman, tek bir dosya (`bdrman.sh`) olarak çalışacak şekilde tasarlanmıştır.

## 1. Dosyayı Sunucuya Yükleme

Repo **Private (Gizli)** olduğu için doğrudan `wget` ile çekemezsiniz. Aşağıdaki yöntemlerden birini kullanın:

### Yöntem A: Token ile İndirme (Önerilen)
GitHub'dan bir "Personal Access Token" (Classic) oluşturun ve aşağıdaki komutu kullanın:
```bash
# TOKEN kısmına kendi tokenınızı yazın
curl -H "Authorization: token GITHUB_TOKEN_BURAYA" -L https://raw.githubusercontent.com/burakdarende/bdrman/main/bdrman.sh -o bdrman.sh
```

### Yöntem B: Manuel Oluşturma
1. Bilgisayarınızdaki `bdrman.sh` içeriğini kopyalayın.
2. Sunucuda boş bir dosya açın: `nano bdrman.sh`
3. İçeriği yapıştırın ve kaydedin (Ctrl+O, Enter, Ctrl+X).

## 2. Otomatik Kurulum Komutu

Dosyayı indirdikten sonra, aşağıdaki komut bloğunu kopyalayıp yapıştırın. Bu komut dosyayı yerine taşıyacak, ismini düzeltecek, izinleri verecek ve çalıştıracaktır:

```bash
# Kurulumu başlat
sudo mv bdrman.sh /usr/local/bin/bdrman && \
sudo chmod +x /usr/local/bin/bdrman && \
sudo bdrman
```

Artık terminalde sadece `bdrman` yazarak programa erişebilirsiniz.

## 2. Opsiyonel Dosyalar

Klasördeki diğer dosyalar zorunlu değildir ancak faydalıdır:

*   **`logrotate.bdrman`**: Log dosyalarının şişmesini engeller. `/etc/logrotate.d/bdrman` konumuna kopyalayabilirsiniz.
*   **`config.conf.example`**: Örnek ayar dosyasıdır. İncelemek için tutabilirsiniz.

*Diğer tüm gereksiz dosyalar (lib, deploy.sh, validate.sh) temizlenmiştir.*
