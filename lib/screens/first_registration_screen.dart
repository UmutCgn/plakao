import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config/shop_config.dart';
import '../models/vehicle.dart';
import '../services/database_service.dart';
import '../services/messaging_service.dart';

/// İlk kayıt akışı.
///
/// ESKİ DAVRANIŞ (hatalı): QR gösterilip "Gönderildi, Kuyruğa Al" butonuna
/// basılırken telefon alanı OPSİYONELDİ. Çalışan numarayı WhatsApp'tan görüp
/// girmeyi unutursa kayıt telefonsuz tamamlanıyor, sonrasında "Bildir"
/// ekranında müşteri numarası hiç çıkmıyordu.
///
/// YENİ DAVRANIŞ: QR ile birlikte aynı ekranda telefon alanı gösterilir ve
/// ZORUNLUDUR. Geçerli bir numara girilmeden kayıt tamamlanamaz; böylece
/// müşteri telefonu hiçbir zaman eksik kalmaz. Tam otomatik (WhatsApp'tan
/// gelen numarayı uygulamanın kendisinin okuması) üçüncü taraf bir backend
/// (WhatsApp Business API) olmadan teknik olarak mümkün değildir — bu yüzden
/// çözüm, çalışanın numarayı gördüğü anda girmesini kolaylaştırıp zorunlu
/// kılmaktır.
class FirstRegistrationScreen extends StatefulWidget {
  final String plate;

  const FirstRegistrationScreen({super.key, required this.plate});

  @override
  State<FirstRegistrationScreen> createState() =>
      _FirstRegistrationScreenState();
}

class _FirstRegistrationScreenState extends State<FirstRegistrationScreen> {
  final _phoneController = TextEditingController();
  final _db = DatabaseService.instance;
  bool _saving = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  String get _qrPayload => MessagingService.buildWhatsAppUri(
        ShopConfig.shopWhatsAppNumber,
        ShopConfig.firstContactMessage(widget.plate),
      ).toString();

  Future<void> _finish() async {
    final rawPhone = _phoneController.text.trim();
    if (!MessagingService.isValidPhone(rawPhone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'İlk kayıtta geçerli bir telefon numarası girmek zorunludur.',
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    await _db.upsertCustomer(widget.plate, rawPhone);
    await _db.addToQueue(
      plate: widget.plate,
      phone: rawPhone,
      status: QueueStatus.inQueue,
    );

    // Dükkan sahibinin numarasından müşteriye hazır karşılama mesajı
    // (WhatsApp -> başarısızsa SMS'e düşer).
    final message = ShopConfig.welcomeMessage(widget.plate);
    await MessagingService.sendWhatsAppOrSms(rawPhone, message);

    if (mounted) {
      setState(() => _saving = false);
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('İlk Kayıt: ${widget.plate}')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Text(
                'Müşteriye QR kodu gösterin. Kendi telefonuyla okutup açılan '
                'WhatsApp mesajını göndersin. Numara ekranınıza düştüğünde '
                'aşağıdaki alana girin — bu adım olmadan kayıt tamamlanmaz.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12),
                  ],
                ),
                child: QrImageView(
                  data: _qrPayload,
                  size: 200,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _phoneController,
                autofocus: true,
                keyboardType: TextInputType.phone,
                style: const TextStyle(fontSize: 20),
                decoration: const InputDecoration(
                  labelText: 'Müşteri Telefon Numarası (zorunlu)',
                  hintText: '05xx xxx xx xx',
                  prefixIcon: Icon(Icons.phone),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _saving ? null : _finish,
                  child: _saving
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Kaydet, Kuyruğa Al ve Mesaj Gönder'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
