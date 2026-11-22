# Plakao

Oto yikama dukkanlari icin tek gorevli, sade, hizli ve cihaz-ici AI destekli
plaka takip ve bildirim uygulamasi.

## Calistirma

```bash
flutter pub get
flutter run
```

Model dosyasi baglanmamis olsa bile uygulama tam calisir: plaka alani
otomatik tahmin yerine bos gelir ve dukkan sahibi elle yazar/duzeltir.

## Kurulum oncesi yapilmasi gerekenler

1. `lib/config/shop_config.dart` icindeki `shopWhatsAppNumber` degerini
   dukkanin gercek WhatsApp numarasiyla degistirin (ulke kodu ile,
   bosluksuz, orn: `905xxxxxxxxx`).
2. İsterseniz ayni dosyadaki hazir mesaj metinlerini (`firstContactMessage`,
   `welcomeMessage`, `readyMessage`) dukkaniniza gore duzenleyin.
3. Gercek cihaz-ici OCR modelini baglamak icin
   `lib/services/plate_recognizer_service.dart` dosyasindaki yonergeleri
   izleyin (tek dosya, tek nokta).

## Akis ozeti

- **Plaka yakalama:** Kamera/galeri -> `PlateRecognizerService` -> dogrudan
  duzenlenebilir metin kutusu.
- **Daimi musteri:** Plaka `customers` tablosunda varsa QR/numara sorulmadan
  direkt kuyruga eklenir.
- **Ilk kayit:** Once QR adimi (musteri kendi telefonundan dukkana hazir
  mesaj gonderir). "QR Okumadi" denirse telefon numarasi girisi zorunludur;
  girildikten sonra dukkan sahibinin telefonundan musteriye karsilama
  mesaji acilir.
- **Bildirim:** Kuyruktaki arac "Hazir" yapilir, ardindan tek dokunusla
  WhatsApp veya SMS uzerinden hazir mesaj gonderilip kayit "teslim edildi"
  durumuna gecer.

## Onemli tasarim notu (QR akisi ve numara)

QR adiminda musteri, kendi telefonundan dukkanin numarasina mesaj gonderir;
uygulama bu gelen mesaji otomatik okuyamaz (WhatsApp'in herkese acik bir
API'si yoktur). Bu yuzden QR adiminda numara alani **opsiyoneldir**:
dukkan sahibi numarayi kendi WhatsApp bildiriminde gorup isterse hizlica
girebilir. Girilmezse, arac yine kuyruga alinir; "Hazir" asamasinda
numara yoksa uygulama o an kisa bir numara giris penceresi acar, boylece
tek tusla bildirim her durumda calisir. Bu, teknik kisitlar icinde
akisi kesintisiz tutan bilincli bir tasarim tercihidir.

## Veritabani

`sqflite` ile iki tablo:
- `customers (plate PK, phone, createdAt)` — daimi musteri eslesmesi.
- `queue_entries (id, plate, phone, status, createdAt, notifiedAt)` —
  gunluk/aktif kuyruk.
