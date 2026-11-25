# Shop Titans botu

Shop Titans'ın Mac sürümü için yazılmış kişisel bir otomasyon denemesi. Anı olarak saklanıyor, geliştirilmiyor.

Tek dosyalık bir Swift programı: ekranı ScreenCaptureKit ile yakalar, Apple Vision ile okur, CGEvent ile tıklar. Ağa, belleğe ya da oyun dosyalarına dokunmaz.

## Neler yapıyor
- Craft, toplama, satış, surcharge / discount / small talk
- Satıcılardan alım, mobilya yükseltme
- Quest: takımı küçültüp boş slotlara dağıtma, dinlenme sürelerine göre bekleme
- Takılınca kurtarma, 3 dakika ilerleme yoksa bekçi

## Sınırlar
- Gem ya da gerçek para harcamaz.
- Oyun robot doğrulaması isterse durur ve kullanıcıyı çağırır. Doğrulamayı cevaplamaz.
- Esc basılı tutulunca durur.

## Çalıştırma
```
./run.sh [dakika=480] [maksCraft=2000]
```
macOS'ta Ekran Kaydı ve Erişilebilirlik izni gerekir. Koordinatlar tek bir ekran düzenine göre ayarlıdır. `logs/` ve test ekran görüntüleri (`fixtures/`) repoda yoktur.

Uyarı: Otomasyon oyunun kurallarına aykırı olabilir ve hesabın kapatılmasına yol açabilir.
