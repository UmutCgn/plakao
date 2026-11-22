# Model Dosyalari

Cihaz-ici plaka tanima modelinizi (.tflite veya .onnx) bu klasore koyun.

Baglama noktasi tek dosyada: `lib/services/plate_recognizer_service.dart`
icindeki `TFLitePlateRecognizerService` sinifi. O dosyadaki yorum satirlari
adim adim neyi nereye ekleyeceginizi gosterir.

Model dosyasi bu klasorde olmasa bile uygulama cokmez: `CaptureScreen`
varsayilan olarak `MockPlateRecognizerService` kullanir ve plaka alani
her zaman elle duzenlenebilir kalir.
