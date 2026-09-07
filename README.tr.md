# Snaplet

**Anında yakala. Net anlat. Güzel paylaş.**

Snaplet, menü çubuğunda yaşayan açık kaynaklı bir macOS yakalama aracıdır. Ekran
görüntüsü alın veya ekranınızı kaydedin, üzerine işaretleme yapın, paylaşılmaması
gerekeni gizleyin ve paylaşmaya değer bir çıktı üretin — hepsi tek uygulamada ve
hepsi kendi Mac'inizde.

- Hesap yok, abonelik yok, reklam yok, watermark yok.
- Telemetri yok, sunucu yok. Snaplet hiçbir ağ isteği göndermez.
- MIT lisanslı.

> **Ad geçicidir.** "Snaplet" adının marka veya App Store çakışması açısından
> kontrolü yapılmadı. Bu adla bir şey yayımlamadan önce ürün adını ve bundle
> kimliğini değiştirin.

---

## İçindekiler

- [Bugün çalışanlar](#bugün-çalışanlar)
- [Gereksinimler](#gereksinimler)
- [Kaynaktan derleme](#kaynaktan-derleme)
- [İzinler](#i̇zinler)
- [Klavye kısayolları](#klavye-kısayolları)
- [Verileriniz nereye gidiyor](#verileriniz-nereye-gidiyor)
- [Mimari](#mimari)
- [Katkı](#katkı)
- [Bilinen sınırlamalar](#bilinen-sınırlamalar)
- [Lisans](#lisans)

---

## Bugün çalışanlar

Aşağıdaki her madde uygulanmış ve uygulama içinden erişilebilir durumdadır.

### Anında yakalama

- Dock simgesi olmayan, siz istemedikçe pencere açmayan menü çubuğu uygulaması.
- Alan, pencere, tam ekran, son alanı tekrarla, kaydı başlat/durdur, ekrandaki
  metni kopyala ve panodaki görseli düzenle için değiştirilebilir genel
  kısayollar.
- Crosshair, karartma, canlı piksel ölçüleri ve piksel büyüteci içeren seçim
  katmanı. ⇧ kareye sabitler, ⌥ merkezden çizer, Boşluk seçimi taşır, Esc iptal
  eder.
- Katman, kendisi görünmeden *önce* alınmış bir anlık görüntüyü çizer; bu yüzden
  Snaplet'in kendi katmanı, önizleme paneli ve kayıt kontrolü çıktıya asla
  giremez.
- Retina ve farklı ölçekli ekranlar desteklenir; bu sürümde seçim tek ekran
  sınırında kalır.
- Son alan tekrarlanırken ekranın hâlâ bağlı olduğu ve dikdörtgenin hâlâ o
  ekranın içinde kaldığı yeniden doğrulanır.
- Çekimler anında panoya gider. Dosya yazmak isteğe bağlıdır.
- Küçük önizleme paneli odağı çalmadan açılır: düzenleyin, kaydedin, Finder'da
  gösterin veya dosyayı doğrudan başka bir uygulamaya sürükleyin.

### Ekran görüntüsü düzenleyicisi

Tahribatsız: kaynak görüntü hiçbir zaman değiştirilmez. Kırpma, döndürme ve her
işaretleme ayrı saklanır ve yalnızca dışa aktarırken uygulanır.

- Kırpma ve döndürme.
- Ok, çizgi, dikdörtgen, elips, serbest çizim, vurgulama.
- Metin, açıklama balonu, otomatik artan numaralı adım işaretleri, büyüteç.
- Blur, pixelate ve opak sansür.
- Renk, kalınlık ve yazı boyutu; nesne seçme, taşıma, yeniden boyutlandırma,
  ok tuşlarıyla kaydırma ve silme; geri al/yinele.
- Kalite ayarıyla PNG veya JPEG dışa aktarma.

Sansür opak bir blok çizer ve bir şeyi gizlemenin önerilen yoludur. Blur ve
pixelate görsel efekt olarak sunulur, güvenlik garantisi olarak değil. Dışa
aktarma her zaman rasterize eder: dosyada tek bir düz görüntü bulunur ve
sansürün altındaki orijinal pikseller dosyaya yazılmaz. Bu davranış, dışa
aktarılan pikselleri geri okuyan testlerle doğrulanır.

### Paylaşıma hazır tasarım

- Düz renk, gradient veya görsel arka plan; ya da hiç arka plan yok.
- Padding, köşe yuvarlaklığı ve gölge.
- Snaplet'in kendi tasarımı olan nötr bir pencere çerçevesi.
- Başlık ve kısa açıklama.
- Orijinal, 1:1, 16:9, 9:16 ve 4:3 çıktı; canlı önizleme ve piksel ölçüleri.
- Beş başlangıç preseti — Sade, Gece, Stüdyo, Dokümantasyon, Sosyal — ve kendi
  kaydettiğiniz presetler.

### Ekran kaydı

- Tam ekran, pencere veya seçili alan kaydı.
- Sistem sesi ve mikrofon birbirinden bağımsız açılır. İkisi de açıkken, bazı
  oynatıcıların yok sayabileceği iki ayrı ses izi yerine ortak bir zaman
  tabanında tek ize karıştırılır.
- İmleç görünürlüğü, tıklama vurgusu, 30 veya 60 FPS, orijinal çözünürlük veya
  1080p/1440p/4K üst sınırı (asla büyütmez), isteğe bağlı geri sayım.
- Yakalandıkça doğrudan diske yazılan MP4 (H.264) çıktısı.
- Menü çubuğunda süre, taşınabilir bir kontrol ve kısayolla durdurma.
- İsteğe bağlı yuvarlak veya yuvarlatılmış webcam katmanı; yalnızca ekranda
  gösterilmez, kodlanan karelere de işlenir.
- Kayıtlar iki saniyelik parçalar hâlinde diske aktarılır; kesintiye uğrayan bir
  oturum bile oynatılabilir bir dosya bırakır. Snaplet başarıyı yalnızca dosya
  sonlandırıldıktan sonra bildirir.

### Hafif video düzenleme

- Başlangıç/bitiş kırpma, önizlemede scrub, herhangi bir kareyi görüntü olarak
  kaydetme.
- Çıktı için sunum stili ve en boy oranı.
- Zaman aralığına bağlı, yumuşak geçişli zoom vurguları.
- Zaman aralığına bağlı metin ve opak sansür kutuları.
- MP4 dışa aktarma ve kısa bir seçim için süre, FPS ve genişlik sınırlı GIF
  dışa aktarma.
- İlerleme göstergesi ve anında iptal.

Önizleme ve dışa aktarma aynı kompozisyonu kullanır; oynatırken gördüğünüz,
yazılan şeydir.

### Hata raporu akışı

- Yerel bir form: başlık, yeniden üretme adımları, beklenen, gerçekleşen.
- Düzenleyicideki numaralı işaretler adım listesinin taslağını oluşturabilir.
- Ortam bilgileri isteğe bağlıdır ve paylaşmadan önce tam olarak gösterilir.
  Snaplet bilgisayar adınızı, kullanıcı adınızı veya dosya yollarınızı asla
  eklemez.
- Çıktı: panoya Markdown veya `report.md` ile medya kopyalarını içeren bir
  dışa aktarma klasörü.

Snaplet GitHub'a bağlanmaz. Rapor, medyanın hiçbir yere yüklenmediğini ve
issue'ya sizin eklemeniz gerektiğini açıkça belirtir.

### Metin tanıma

- Kısayolla, seçili alandaki metni doğrudan panoya kopyalayın.
- Düzenleyicide bir ekran görüntüsündeki metni okuyun ve seçtiğiniz satırları
  kopyalayın.
- Geçmişinizde tanınan metne göre arama yapın.
- Hassas olabilecek alanlar için öneriler — e-posta adresleri, anahtar benzeri
  diziler, token'lar, IP adresleri, uzun numaralar — hiçbir şey gizlenmeden önce
  sizin onayınızdan geçer.

Tanıma, bu Mac üzerinde Apple'ın Vision çatısıyla ve ana thread dışında çalışır.
Bulut yapay zekâ, API anahtarı veya uzak OCR servisi yoktur. Öneriler, tanınan
metin üzerinde örüntü eşleştirmedir: bazı şeyleri kaçırır, zararsız olanları da
işaretleyebilir.

### Geçmiş ve ayarlar

- Görüntü/video filtreleri, küçük önizlemeler, favoriler ve dosya adı ile
  tanınan metinde arama içeren yerel geçmiş.
- Bir öğeyi düzenleyicide yeniden açın, Finder'da gösterin, geçmişten kaldırın
  veya dosyayı Çöp Kutusu'na taşıyın — son iki seçenek arasındaki fark arayüzde
  açıkça belirtilir.
- Metadata küçük bir SwiftData deposunda tutulur; medya dosyaları çıktı
  klasörünüzde kalır ve veritabanına kopyalanmaz.
- Kısayollar, çıktı klasörü, pano ve otomatik kaydetme davranışı, görüntü
  biçimi, varsayılan stil, kayıt kalitesi ve sesi, webcam katmanı, tema, dil,
  girişte başlatma ve geçmiş ile metin dizinini temizleme ayarları.
- Snaplet kendi başına çekim dosyalarınızı silmez.

---

## Gereksinimler

- macOS 15 veya üzeri.
- Kaynaktan derlemek için Xcode 26 veya üzeri.
- Geliştirme ve test hedefi Apple Silicon'dır. Proje Intel için de derlenir ama
  Snaplet bir Intel Mac'te test edilmedi; bu yüzden bu konuda bir iddia
  edilmiyor.

## Kaynaktan derleme

```bash
git clone https://github.com/berkcangumusisik/mac-screen-recorder.git
cd mac-screen-recorder
open Snaplet.xcodeproj
```

**Snaplet** şemasını seçip çalıştırın. Komut satırından:

```bash
xcodebuild -project Snaplet.xcodeproj -scheme Snaplet -configuration Debug -destination 'platform=macOS' build
```

Testleri çalıştırma:

```bash
./scripts/run-tests.sh
```

`dist/` içine Release `.app` ve zip üretme:

```bash
./scripts/build-release.sh
```

Varsayılan derleme ad-hoc imzalar (`CODE_SIGN_IDENTITY = "-"`); bu, Snaplet'i
derlendiği Mac'te çalıştırmak için yeterlidir. Başka makinelere dağıtım için
imzalama ve notarization gerekir — bkz.
[docs/signing-and-notarization.md](docs/signing-and-notarization.md).

## İzinler

Snaplet bir izni yalnızca o izne ihtiyaç duyan özelliği ilk kez kullandığınızda
ister.

| İzin | Ne için gerekli | Ne zaman isteniyor |
| --- | --- | --- |
| Ekran ve Sistem Sesi Kaydı | Her ekran görüntüsü ve kayıt | İlk çekimde |
| Mikrofon | Kayıtta anlatım | "Mikrofonu kaydet" açıkken ilk kayıtta |
| Kamera | Webcam katmanı | Katman açıkken ilk kayıtta |

Başka hiçbir izin istenmez. Snaplet'in Erişilebilirlik iznine ihtiyacı yoktur:
genel kısayollar Carbon hot key'leri kullanır ve sistem bunları yalnızca
Snaplet'in kaydettiği tam kombinasyonlar için iletir. Snaplet genel klavye
girdisini hiçbir zaman izlemez. Tıklama vurgusu sistemin yakalama katmanı
tarafından çizilir ve ek izin gerektirmez.

Bir izni reddederseniz Snaplet neyin eksik olduğunu söyler ve doğru Sistem
Ayarları bölümünü açmayı önerir. İzni sonradan vermek yeniden başlatma
gerektirmez.

Debug derlemesi ad-hoc imzalandığı için, yeniden derleme imzayı değiştirdiğinde
macOS izni tekrar sorabilir.

## Klavye kısayolları

Varsayılanlar ⌃⌥⌘ kullanır; böylece macOS'un yerleşik ekran görüntüsü
kısayollarıyla (⇧⌘3/4/5/6) çakışmaz. Hepsi Ayarlar › Kısayollar bölümünden
değiştirilebilir ve sistemin reddettiği her kısayol orada bildirilir.

| İşlem | Varsayılan |
| --- | --- |
| Alan yakala | ⌃⌥⌘A |
| Pencere yakala | ⌃⌥⌘W |
| Tam ekran yakala | ⌃⌥⌘F |
| Son alanı tekrarla | ⌃⌥⌘R |
| Kaydı başlat / durdur | ⌃⌥⌘V |
| Ekrandaki metni kopyala | ⌃⌥⌘T |
| Panodaki görseli düzenle | ⌃⌥⌘E |

Seçim sırasında: ⇧ kare, ⌥ merkezden, Boşluk taşı, Esc iptal.
Düzenleyicide tek tuşlar araç değiştirir (V, C, A, L, R, O, D, H, T, B, S, M, U,
P, X); ⌘Z / ⇧⌘Z geri alır ve yineler.

## Verileriniz nereye gidiyor

Her çekim, düzenleme, tanıma ve dışa aktarma Mac'inizde gerçekleşir:

- Ekran görüntüleri ve kayıtlar ScreenCaptureKit ile üretilir ve seçtiğiniz
  çıktı klasörüne yazılır (varsayılan `~/Pictures/Snaplet`).
- Düzenleme bellekte yapılır; dışa aktarma ImageIO ve AVFoundation ile yazılır.
- Metin tanıma Apple'ın Vision çatısıyla yerel olarak çalışır.
- Geçmiş metadata'sı `~/Library/Application Support/Snaplet` içinde, küçük JPEG
  önizlemeler yanında tutulur. Medyaya yol üzerinden referans verilir, kopya
  alınmaz.
- Tercihler uygulamanın `UserDefaults` alanında saklanır.

Snaplet'te analitik SDK'sı, çökme raporlayıcısı veya ağ kodu yoktur. Tek
bağımlılığı Apple çatılarıdır; üçüncü taraf paket bulunmaz, dolayısıyla
denetlenecek başka bir şey yoktur.

Loglama bilinçli olarak dardır: Snaplet yalnızca yaşam döngüsü ve hata bilgisi
loglar. Yakalanan pikseller, tanınan metin, pencere başlıkları ve dosya yolları
loga yazılmaz.

## Mimari

```
Snaplet/
  App/           Kompozisyon kökü, menü çubuğu, ana menü, app delegate
  Core/          Hatalar, loglama, koordinat dönüşümü, görüntü dışa aktarma, geçici dosyalar, ölçümler
  Permissions/   Ekran, mikrofon ve kamera izin durumu
  Hotkeys/       Kısayol modeli, Carbon kaydı, tuş kodu çevirisi
  Capture/       ScreenCaptureKit görüntüleri, seçim katmanı, yakalama koordinatörü
  Editor/        Tahribatsız doküman, işaretlemeler, renderer, tuval, denetçiler
  Presentation/  Stil presetleri ve paylaşıma hazır renderer
  Recording/     Yapılandırma, durum makinesi, writer, ses karıştırıcı, webcam, kompozitör
  VideoEditor/   Düzenleme modeli, kare renderer, kompozisyon, dışa aktarıcı, arayüz
  OCR/           Vision tanıma ve hassas örüntü önerileri
  Library/       SwiftData geçmiş deposu ve penceresi
  BugReport/     Rapor modeli ve formu
  Settings/      Tercihler, depo, ayar arayüzü, kısayol kaydedici
  UI/            Önizleme paneli, hata sunumu, yardım penceresi
```

Bütünü üç fikir bir arada tutuyor:

1. **Tek koordinat otoritesi.** AppKit noktaları, Core Graphics ekran noktaları
   ve görüntü pikselleri arasındaki dönüşümü yalnızca `ScreenGeometry` yapar.
   Bütün yakalama yolları buradan geçer ve negatif orijinli, ikincil ekran
   yerleşimleri dahil testlerle kapsanır.
2. **Ortam başına tek renderer.** Ekran görüntüleri için `AnnotationRenderer`,
   video için `VideoFrameRenderer`. Düzenleyici önizlemesi ile dışa aktarıcı
   aynı kodu çağırır; önizleme yazılandan sapamaz.
3. **Açık yaşam döngüleri.** Kaydın gerçek bir durum makinesi vardır
   (`RecordingState`); geçişleri doğrulanır ve test edilir. Dışa aktarmalar
   iptal edilebilir işlerdir; stream, observer ve task'lar onları oluşturan
   yolda kapatılır.

Ele alınan uç durumlar: iznin reddedilmesi ve sonradan verilmesi, art arda
kısayol basılması, kayıt sürerken yeniden başlatma, hedef pencerenin kapanması,
monitörün çıkarılması, uyku, diskin dolması, dışa aktarmanın iptali ve kayıt
sürerken uygulamadan çıkma (kısmi dosya sonlandırılıp saklanır).

Ölçülmüş performans sayıları ve bunların nasıl tekrarlanacağı
[docs/performance.md](docs/performance.md) dosyasındadır.

## Katkı

Hata bildirimleri ve pull request'ler memnuniyetle karşılanır. Yerleşim, test
kuralları ve bir değişikliğin incelemeden önce ne gerektirdiği için
[CONTRIBUTING.md](CONTRIBUTING.md) ile başlayın. Katılan herkesin
[Davranış Kuralları](CODE_OF_CONDUCT.md) belgesine uyması beklenir.

Güvenlik konuları: bkz. [SECURITY.md](SECURITY.md).

## Bilinen sınırlamalar

- Seçim iki ekrana yayılamaz; sürüklemenin başladığı ekranda kalır.
- Kayıt duraklatılıp sürdürülemez. Durdurmak dosyayı sonlandırır.
- Otomatik nesne takibi ve otomatik sinematik zoom yoktur; zoom vurguları elle
  yerleştirilir.
- Video düzenleme bilinçli olarak küçüktür: kırpma, stil, zoom, metin ve sansür.
  Zaman çizelgeli bir editör değildir ve çoklu klip desteği yoktur.
- GIF dışa aktarma 30 saniye, 15 FPS ve 800 px genişlikle sınırlıdır.
- Hassas metin önerileri yalnızca Vision'ın okuyabildiğini görür ve şekle göre
  eşleşir. Bunları bir garanti değil, "bir bak" uyarısı olarak değerlendirin.
- Blur ve pixelate görsel efekttir. Önemli bir şey için sansürü kullanın.
- Snaplet bir Intel Mac'te test edilmedi.
- Türkçe çeviri mevcut metinler için eksiksizdir; yeni metinler için sürümden
  önce `./scripts/sync-strings.sh` çalıştırılmalıdır.
- Henüz bir uygulama simgesi yok; menü çubuğu öğesi bir SF Symbol kullanıyor.
- Ekran görüntüsü veya demo videosu eklenmedi; bunlar ekran kaydı izni olan bir
  makinede üretilmelidir. Çekilecek senaryolar
  [docs/demo-scenarios.md](docs/demo-scenarios.md) dosyasında yazılıdır.

Planlanan işler [ROADMAP.md](ROADMAP.md) dosyasındadır.

## Lisans

MIT — bkz. [LICENSE](LICENSE).
