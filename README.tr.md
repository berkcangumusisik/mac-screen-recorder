<div align="center">

<img src="docs/images/icon.png" width="128" alt="Snaplet">

# Snaplet

**Anında yakala. Net anlat. Güzel paylaş.**

Menü çubuğunda yaşayan, açık kaynaklı bir macOS yakalama aracı.<br>
Ekran görüntüsü alın, kaydedin, işaretleyin, paylaşılmaması gerekeni gizleyin ve
teslim edin — tek uygulamada, kendi Mac'inizde.

[![Lisans: MIT](https://img.shields.io/badge/lisans-MIT-blue.svg)](LICENSE)
[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-000000?logo=apple&logoColor=white)](#gereksinimler)
[![Swift](https://img.shields.io/badge/Swift-Xcode%2026-F05138?logo=swift&logoColor=white)](#kaynaktan-derleme)
[![Telemetri: yok](https://img.shields.io/badge/telemetri-yok-2ea44f)](#gizlilik)
[![CI](https://github.com/berkcangumusisik/mac-screen-recorder/actions/workflows/ci.yml/badge.svg)](https://github.com/berkcangumusisik/mac-screen-recorder/actions/workflows/ci.yml)

[English README](README.md)

</div>

---

## Neden Snaplet

Çoğu yakalama aracı sizi seçim yapmaya zorlar: ya hızlı bir kısayol, ya gerçek
bir düzenleyici, ya kayıt, ya da sonucu sunulabilir hale getiren bir şey.
Snaplet dördü birden ve ekranınızı hiçbir yere göndermiyor.

- **Her şey Mac'inizde kalır.** Hesap yok, abonelik yok, reklam yok, watermark
  yok, telemetri yok. Snaplet'te hiç ağ kodu bulunmuyor.
- **Uçtan uca tek uygulama.** Bir tuşa basın, işaretleyin, unuttuğunuz token'ı
  sansürleyin, bir gradyanın üstüne yerleştirin, dışa aktarın. Üç uygulama
  arasında gidip gelmek yok.
- **Sınırları konusunda dürüst.** Sansür opaktır; blur "görsel efekt" olarak
  adlandırılır, garanti olarak değil. Bu README'de yapılmamış hiçbir özellik
  yapılmış gibi anlatılmaz.
- **MIT lisanslı**, üçüncü taraf bağımlılığı yok — yalnızca Apple çatıları.

> [!NOTE]
> **Ad geçicidir.** "Snaplet" adı marka veya App Store çakışması açısından
> kontrol edilmedi. Bu adla bir şey yayımlamadan önce ürün adını ve bundle
> kimliğini değiştirin.

---

## Hızlı başlangıç

```bash
git clone https://github.com/berkcangumusisik/mac-screen-recorder.git
cd mac-screen-recorder
open Snaplet.xcodeproj      # Snaplet şemasını seçip çalıştırın
```

Snaplet menü çubuğunda belirir — Dock simgesi yok, pencere yok. **⌃⌥⌘A** ile
sürükleyip yakalayın; tuşu bırakmadan görüntü panonuzda olur.

---

## Özellikler

| | |
|---|---|
| **Anında yakalama** | Alan, pencere, tam ekran, son alanı tekrarla — her biri değiştirilebilir kendi genel kısayoluyla |
| **Ekran görüntüsü düzenleyicisi** | Tahribatsız: ok, şekil, serbest çizim, metin, açıklama balonu, numaralı adımlar, büyüteç, blur, pixelate, opak sansür |
| **Paylaşıma hazır tasarım** | Arka planlar, boşluk, gölge, nötr pencere çerçevesi, başlık, sosyal medya oranları, kaydedilebilir presetler |
| **Ekran kaydı** | Sistem sesi, mikrofon, imleç, tıklama vurgusu ve videoya işlenen webcam katmanıyla MP4 |
| **Hafif video düzenleme** | Kırpma, zoom vurguları, zaman aralıklı metin ve sansür, ilerleme ve iptalli MP4 ile GIF dışa aktarma |
| **Cihaz üzerinde metin tanıma** | Ekrandaki metni kopyalayın, geçmişte metne göre arayın, hassas görünen alanlar için öneri alın |
| **Yerel geçmiş** | Küçük önizlemeler, favoriler, filtreler, dosya adı ve tanınan metinde arama |
| **Hata raporu akışı** | Medyası yanında duran yerel Markdown raporu; işaretlemediğiniz hiçbir bilgi eklenmez |

<details>
<summary><strong>Anında yakalama — ayrıntılar</strong></summary>

- Dock simgesi olmayan, siz istemedikçe pencere açmayan menü çubuğu uygulaması.
- Alan, pencere, tam ekran, son alanı tekrarla, kaydı başlat/durdur, ekrandaki
  metni kopyala ve panodaki görseli düzenle için değiştirilebilir genel
  kısayollar.
- Crosshair, karartma, canlı piksel ölçüleri ve piksel büyüteci içeren seçim
  katmanı. ⇧ kareye sabitler, ⌥ merkezden çizer, Boşluk seçimi taşır, Esc iptal
  eder.
- Katman, kendisi görünmeden *önce* alınmış bir anlık görüntüyü çizer; bu yüzden
  Snaplet'in kendi katmanı, önizleme paneli ve kayıt kontrolü çıktıya asla
  giremez — ve seçimi onaylamak ikinci bir yakalama gerektirmez.
- Retina ve farklı ölçekli ekranlar desteklenir; bu sürümde seçim tek ekran
  sınırında kalır.
- Son alan tekrarlanırken ekranın hâlâ bağlı olduğu ve dikdörtgenin hâlâ o
  ekranın içinde kaldığı yeniden doğrulanır.
- Çekimler anında panoya gider. Dosya yazmak isteğe bağlıdır.
- Küçük önizleme paneli odağı çalmadan açılır: düzenleyin, kaydedin, Finder'da
  gösterin veya dosyayı doğrudan başka bir uygulamaya sürükleyin.

</details>

<details>
<summary><strong>Ekran görüntüsü düzenleyicisi — ayrıntılar</strong></summary>

Tahribatsız: kaynak görüntü hiçbir zaman değiştirilmez. Kırpma, döndürme ve her
işaretleme ayrı saklanır ve yalnızca dışa aktarırken uygulanır.

- Kırpma ve döndürme.
- Ok, çizgi, dikdörtgen, elips, serbest çizim, vurgulama.
- Metin, açıklama balonu, otomatik artan numaralı adım işaretleri, büyüteç.
- Blur, pixelate ve opak sansür.
- Renk, kalınlık ve yazı boyutu; nesne seçme, taşıma, yeniden boyutlandırma, ok
  tuşlarıyla kaydırma ve silme; geri al/yinele.
- Kalite ayarıyla PNG veya JPEG dışa aktarma.

Sansür opak bir blok çizer ve bir şeyi gizlemenin önerilen yoludur. Blur ve
pixelate görsel efekt olarak sunulur, güvenlik garantisi olarak değil. Dışa
aktarma her zaman rasterize eder: dosyada tek bir düz görüntü bulunur ve sansürün
altındaki orijinal pikseller dosyaya yazılmaz. Testler bunu kanıtlamak için dışa
aktarılan pikselleri geri okur.

</details>

<details>
<summary><strong>Paylaşıma hazır tasarım — ayrıntılar</strong></summary>

- Düz renk, gradient veya görsel arka plan; ya da hiç arka plan yok.
- Padding, köşe yuvarlaklığı ve gölge.
- Snaplet'in kendi tasarımı olan nötr bir pencere çerçevesi.
- Başlık ve kısa açıklama.
- Orijinal, 1:1, 16:9, 9:16 ve 4:3 çıktı; canlı önizleme ve piksel ölçüleri.
- Beş başlangıç preseti — Sade, Gece, Stüdyo, Dokümantasyon, Sosyal — ve kendi
  kaydettiğiniz presetler.

</details>

<details>
<summary><strong>Ekran kaydı — ayrıntılar</strong></summary>

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

</details>

<details>
<summary><strong>Hafif video düzenleme — ayrıntılar</strong></summary>

- Başlangıç/bitiş kırpma, önizlemede scrub, herhangi bir kareyi görüntü olarak
  kaydetme.
- Çıktı için sunum stili ve en boy oranı.
- Zaman aralığına bağlı, yumuşak geçişli zoom vurguları.
- Zaman aralığına bağlı metin ve opak sansür kutuları.
- MP4 dışa aktarma ve kısa bir seçim için süre, FPS ve genişlik sınırlı GIF dışa
  aktarma.
- İlerleme göstergesi ve anında iptal.

Önizleme ve dışa aktarma aynı kompozisyonu kullanır; oynatırken gördüğünüz,
yazılan şeydir.

</details>

<details>
<summary><strong>Metin tanıma, geçmiş ve hata raporları — ayrıntılar</strong></summary>

**Metin tanıma**, bu Mac üzerinde Apple'ın Vision çatısıyla ve ana thread dışında
çalışır. Bulut yapay zekâ, API anahtarı veya uzak OCR servisi yoktur.

- Kısayolla, seçili alandaki metni doğrudan panoya kopyalayın.
- Düzenleyicide bir ekran görüntüsündeki metni okuyun ve seçtiğiniz satırları
  kopyalayın.
- Geçmişinizde tanınan metne göre arama yapın.
- Hassas olabilecek alanlar için öneriler — e-posta adresleri, anahtar benzeri
  diziler, token'lar, IP adresleri, uzun numaralar — hiçbir şey gizlenmeden önce
  sizin onayınızdan geçer. Bunlar Vision'ın okuyabildiği metin üzerinde örüntü
  eşleşmeleridir: bazı şeyleri kaçırır, zararsız olanları da işaretleyebilir.

**Geçmiş** yalnızca metadata saklar — yol, boyut, tanınan metin ve küçük bir
önizleme dosyası. Medya çıktı klasörünüzde kalır, veritabanına kopyalanmaz. Bir
öğeyi yeniden açın, Finder'da gösterin, geçmişten kaldırın veya dosyayı Çöp
Kutusu'na taşıyın; son iki seçenek arasındaki fark arayüzde açıkça belirtilir.
Snaplet kendi başına çekim dosyalarınızı silmez.

**Hata raporları** yerel olarak yazılır: başlık, adımlar, beklenen ve gerçekleşen
için bir form; düzenleyicideki numaralı işaretler adım listesinin taslağını
oluşturabilir. Ortam bilgileri isteğe bağlıdır ve paylaşmadan önce tam olarak
gösterilir — bilgisayar adınız, kullanıcı adınız ve dosya yollarınız asla
eklenmez. Çıktı, panoya Markdown veya medyanın yanında durduğu bir dışa aktarma
klasörüdür. Snaplet GitHub'a bağlanmaz ve rapor, medyayı sizin eklemeniz
gerektiğini açıkça belirtir.

</details>

---

## Gereksinimler

| | |
|---|---|
| macOS | 15 veya üzeri |
| Xcode | 26 veya üzeri (kaynaktan derlemek için) |
| Mimari | Geliştirme ve test hedefi Apple Silicon. Proje Intel için de derlenir ama orada test edilmedi; bu yüzden bir iddia edilmiyor. |
| Bağımlılık | Yok. Yalnızca Apple çatıları. |

## Kaynaktan derleme

```bash
xcodebuild -project Snaplet.xcodeproj -scheme Snaplet -configuration Debug -destination 'platform=macOS' build
```

```bash
./scripts/run-tests.sh        # tüm test paketi
./scripts/build-release.sh    # dist/ içine Release .app + zip
```

Varsayılan derleme ad-hoc imzalar; bu, Snaplet'i derlendiği Mac'te çalıştırmak
için yeterlidir. Başka makinelere dağıtım imzalama ve notarization gerektirir —
bkz. [docs/signing-and-notarization.md](docs/signing-and-notarization.md).

> [!IMPORTANT]
> Ad-hoc imza ikiliden türetilir, yani her derlemede değişir; macOS da Ekran ve
> Sistem Sesi Kaydı iznini imzaya bağlar. Her yeniden derlemeden sonra bu izni
> tekrar vermeniz gerekir. Geliştirme sırasında sabit, kendinden imzalı bir
> sertifikayla imzalamak bunu ortadan kaldırır — bkz.
> [Yeniden derlemelerde izni korumak](docs/signing-and-notarization.md#1b-keeping-permissions-across-rebuilds).

<details>
<summary><strong>Uygulama simgesini yeniden üretmek</strong></summary>

Simge, hazır bir görsel olarak depoya konmak yerine kaynaktan üretilir; böylece
diğer dosyalar gibi incelenip değiştirilebilir:

```bash
swift scripts/make-app-icon.swift
```

Bütün boyutları `Snaplet/Resources/Assets.xcassets/AppIcon.appiconset` içine ve
1024 px'lik bir önizlemeyi `build/icon-preview.png` konumuna yazar. 16 ve 32
piksellik boyutlar kendi daha kalın geometrileriyle çizilir; çünkü tam çizimi
küçültmek bu boyutlarda okunmaz bir lekeye dönüşüyor. Menü çubuğu öğesi bilinçli
olarak SF Symbol kullanmaya devam eder, böylece açık ve koyu temada sistemin
template görsel davranışını izler.

</details>

## İzinler

Snaplet bir izni yalnızca o izne ihtiyaç duyan özelliği ilk kez kullandığınızda
ister.

| İzin | Ne için gerekli | Ne zaman isteniyor |
| --- | --- | --- |
| Ekran ve Sistem Sesi Kaydı | Her ekran görüntüsü ve kayıt | İlk çekimde |
| Mikrofon | Kayıtta anlatım | "Mikrofonu kaydet" açıkken ilk kayıtta |
| Kamera | Webcam katmanı | Katman açıkken ilk kayıtta |

Başka hiçbir izin istenmez. Snaplet'in Erişilebilirlik iznine **ihtiyacı yoktur**:
genel kısayollar Carbon hot key'leri kullanır ve sistem bunları yalnızca
Snaplet'in kaydettiği tam kombinasyonlar için iletir. Snaplet genel klavye
girdisini hiçbir zaman izlemez. Tıklama vurgusu sistemin yakalama katmanı
tarafından çizilir ve ek izin gerektirmez.

Bir izni reddederseniz Snaplet neyin eksik olduğunu söyler ve doğru Sistem
Ayarları bölümünü açmayı önerir. İzni sonradan vermek yeniden başlatma
gerektirmez: Snaplet, macOS'un süreç için önbelleğe aldığı değere güvenmek yerine
ScreenCaptureKit ile doğrular.

## Klavye kısayolları

Varsayılanlar ⌃⌥⌘ kullanır; böylece macOS'un yerleşik ekran görüntüsü
kısayollarıyla (⇧⌘3/4/5/6) çakışmaz. Hepsi Ayarlar › Kısayollar bölümünden
değiştirilebilir ve sistemin reddettiği her kısayol orada bildirilir.

| İşlem | Varsayılan |
| --- | --- |
| Alan yakala | <kbd>⌃⌥⌘A</kbd> |
| Pencere yakala | <kbd>⌃⌥⌘W</kbd> |
| Tam ekran yakala | <kbd>⌃⌥⌘F</kbd> |
| Son alanı tekrarla | <kbd>⌃⌥⌘R</kbd> |
| Kaydı başlat / durdur | <kbd>⌃⌥⌘V</kbd> |
| Ekrandaki metni kopyala | <kbd>⌃⌥⌘T</kbd> |
| Panodaki görseli düzenle | <kbd>⌃⌥⌘E</kbd> |

Seçim sırasında: <kbd>⇧</kbd> kare, <kbd>⌥</kbd> merkezden, <kbd>Boşluk</kbd>
taşı, <kbd>Esc</kbd> iptal. Düzenleyicide tek tuşlar araç değiştirir
(V, C, A, L, R, O, D, H, T, B, S, M, U, P, X); <kbd>⌘Z</kbd> / <kbd>⇧⌘Z</kbd>
geri alır ve yineler.

---

## Gizlilik

Her çekim, düzenleme, tanıma ve dışa aktarma Mac'inizde gerçekleşir:

- Ekran görüntüleri ve kayıtlar ScreenCaptureKit ile üretilir ve seçtiğiniz çıktı
  klasörüne yazılır (varsayılan `~/Pictures/Snaplet`).
- Düzenleme bellekte yapılır; dışa aktarma ImageIO ve AVFoundation ile yazılır.
- Metin tanıma Apple'ın Vision çatısıyla yerel olarak çalışır.
- Geçmiş metadata'sı `~/Library/Application Support/Snaplet` içinde, küçük JPEG
  önizlemeler yanında tutulur. Medyaya yol üzerinden referans verilir, kopya
  alınmaz.
- Tercihler uygulamanın `UserDefaults` alanında saklanır.

Snaplet'te analitik SDK'sı, çökme raporlayıcısı veya ağ kodu yoktur. Tek
bağımlılığı Apple çatılarıdır; denetlenecek başka bir şey yoktur.

Loglama bilinçli olarak dardır: yalnızca yaşam döngüsü ve hata bilgisi. Yakalanan
pikseller, tanınan metin, pencere başlıkları ve dosya yolları loga yazılmaz.

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

1. **Tek koordinat otoritesi.** AppKit noktaları, Core Graphics ekran noktaları ve
   görüntü pikselleri arasındaki dönüşümü yalnızca `ScreenGeometry` yapar. Bütün
   yakalama yolları buradan geçer ve negatif orijinli, ikincil ekran yerleşimleri
   dahil testlerle kapsanır.
2. **Ortam başına tek renderer.** Ekran görüntüleri için `AnnotationRenderer`,
   video için `VideoFrameRenderer`. Düzenleyici önizlemesi ile dışa aktarıcı aynı
   kodu çağırır; önizleme yazılandan sapamaz.
3. **Açık yaşam döngüleri.** Kaydın gerçek bir durum makinesi vardır
   (`RecordingState`); geçişleri doğrulanır ve test edilir. Dışa aktarmalar iptal
   edilebilir işlerdir; stream, observer ve task'lar onları oluşturan yolda
   kapatılır.

Ele alınan uç durumlar: iznin reddedilmesi ve sonradan verilmesi, art arda kısayol
basılması, kayıt sürerken yeniden başlatma, hedef pencerenin kapanması, monitörün
çıkarılması, uyku, diskin dolması, dışa aktarmanın iptali ve kayıt sürerken
uygulamadan çıkma (kısmi dosya sonlandırılıp saklanır).

**Testler.** 122 birim ve entegrasyon testi; hataların pahalıya mal olduğu
yerlere odaklanır: koordinat dönüşümü, döndürme dönüşümleri, kayıt durum
geçişleri, ses karıştırma, zaman aralıkları, dosya bütünlüğü ve sansürlü çıktı —
testin kendi yazdığı gerçek bir MP4'ü geri işleyip sansürün zoom ve stil altında
aralığın her karesini kapattığını doğrulamak dahil.

Ölçülmüş performans sayıları ve nasıl tekrarlanacağı
[docs/performance.md](docs/performance.md) dosyasındadır.

---

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
- Ekran görüntüsü veya demo videosu eklenmedi; bunlar ekran kaydı izni olan bir
  makinede üretilmelidir. Çekilecek senaryolar
  [docs/demo-scenarios.md](docs/demo-scenarios.md) dosyasında yazılıdır.

Planlanan işler [ROADMAP.md](ROADMAP.md) dosyasındadır.

## Lisans

MIT — bkz. [LICENSE](LICENSE).
