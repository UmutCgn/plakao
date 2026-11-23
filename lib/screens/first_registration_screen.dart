import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config/shop_config.dart';
import '../models/vehicle.dart';
import '../services/database_service.dart';
import '../services/messaging_service.dart';

/// İlk kayıt akışı — iki adımlı:
///
/// 1) QR ADIMI: Müşteriye QR gösterilir. QR, dükkanın WhatsApp numarasına
///    (https://wa.me/<dükkan_no>?text=<mesaj>) hazır mesajla gider. Müşteri
///    kendi telefonuyla QR'ı okutup açılan WhatsApp'ta "Gönder"e basar —
///    uygulama indirmesine gerek kalmaz.
///
/// 2) DOĞRULAMA ADIMI: Müşteri QR'ı okutup mesajı attıktan HEMEN SONRA,
///    dükkanın WhatsApp'ına gelen bildirimde numara görünür. Personel "Gönderdi"
///    deyip bir sonraki adıma geçer ve bildirimde gördüğü numarayı buraya
///    girerek doğrular. Numara bu adımda veritabanına kaydedilir ve kayıt
///    kuyruğa alınır.
///
/// NOT: Müşterinin QR ile attığı WhatsApp mesajının içeriği/gönderen numarası
/// bu uygulamaya OTOMATİK olarak aktarılamaz (iki ayrı hesap/cihaz arasında
/// senkronizasyon, sunucu + WhatsApp Business API olmadan teknik olarak mümkün
/// değildir). Bu yüzden doğrulama adımı personelin bildirimde gördüğü numarayı
/// elle girmesiyle çalışır. QR okutulamazsa (kamera yok, müşteri istemiyor vb.)
/// "Numarasız devam et" ile kayıt numarasız da tamamlanabilir.
enum _RegistrationStep { qr, verifyPhone }

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
  _RegistrationStep _step = _RegistrationStep.qr;
  bool _saving = false;
  int _visitNumber = 1;

  @override
  void initState() {
    super.initState();
    _loadVisitNumber();
  }

  Future<void> _loadVisitNumber() async {
    final previous = await _db.getVisitCount(widget.plate);
    if (!mounted) return;
    setState(() => _visitNumber = previous + 1);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  String get _qrPayload => MessagingService.buildWhatsAppUri(
        ShopConfig.shopWhatsAppNumber,
        ShopConfig.firstContactMessage(widget.plate, visitCount: _visitNumber),
      ).toString();

  void _goToVerifyStep() {
    setState(() => _step = _RegistrationStep.verifyPhone);
  }

  void _backToQrStep() {
    setState(() => _step = _RegistrationStep.qr);
  }

  /// Doğrulama adımında girilen numarayı kaydeder, müşteriye karşılama
  /// mesajı gönderir ve kaydı kuyruğa alır.
  Future<void> _confirmPhoneAndFinish() async {
    if (_saving) return;
    final rawPhone = _phoneController.text.trim();

    if (rawPhone.isEmpty || !MessagingService.isValidPhone(rawPhone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bildirimde gördüğünüz numarayı eksiksiz girin (05xx xxx xx xx). '
            'Numara yoksa "Numarasız devam et" seçeneğini kullanın.',
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    await _db.addToQueue(
      plate: widget.plate,
      phone: rawPhone,
      status: QueueStatus.inQueue,
    );
    await _db.upsertCustomer(widget.plate, rawPhone);

    final message =
        ShopConfig.welcomeMessage(widget.plate, visitCount: _visitNumber);
    await MessagingService.sendWhatsAppOrSms(rawPhone, message);

    if (mounted) {
      setState(() => _saving = false);
      Navigator.of(context).pop(true);
    }
  }

  /// QR okutulamadığı ya da numara doğrulanamadığı durumlar için: kayıt
  /// numarasız da tamamlanabilir.
  Future<void> _finishWithoutPhone() async {
    if (_saving) return;
    setState(() => _saving = true);

    await _db.addToQueue(
      plate: widget.plate,
      phone: null,
      status: QueueStatus.inQueue,
    );

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
          child: _step == _RegistrationStep.qr
              ? _buildQrStep()
              : _buildVerifyStep(),
        ),
      ),
    );
  }

  Widget _buildQrStep() {
    return Column(
      children: [
        const _StepBadge(step: 1, total: 2, label: 'QR Gösterilsin'),
        const SizedBox(height: 12),
        const Text(
          'Müşteriye QR kodu gösterin. Kendi telefonuyla okutup açılan '
          'WhatsApp mesajını göndermesi yeterlidir. Müşteri "Gönder"e '
          'basınca numarası bildirim olarak dükkanın WhatsApp\'ına düşer.',
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
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _goToVerifyStep,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Müşteri Gönderdi, Numarayı Gir →'),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _saving ? null : _finishWithoutPhone,
          child: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('QR okutulamıyor, numarasız devam et'),
        ),
      ],
    );
  }

  Widget _buildVerifyStep() {
    return Column(
      children: [
        const _StepBadge(step: 2, total: 2, label: 'Numarayı Doğrula'),
        const SizedBox(height: 12),
        const Text(
          'Dükkanın WhatsApp\'ına düşen bildirimde gördüğünüz numarayı '
          'aşağıya girin ve doğrulayın. Bu numara kaydedilip müşteriye '
          'yıkama bittiğinde haber vermek için kullanılacak.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _phoneController,
          autofocus: true,
          keyboardType: TextInputType.phone,
          style: const TextStyle(fontSize: 20),
          decoration: const InputDecoration(
            labelText: 'Bildirimdeki Müşteri Numarası',
            hintText: '05xx xxx xx xx',
            prefixIcon: Icon(Icons.phone_android),
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _saving ? null : _confirmPhoneAndFinish,
            icon: _saving ? const SizedBox.shrink() : const Icon(Icons.verified_outlined),
            label: _saving
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Doğrula, Kaydet ve Kuyruğa Al'),
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _saving ? null : _backToQrStep,
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('QR\'a dön'),
        ),
        TextButton(
          onPressed: _saving ? null : _finishWithoutPhone,
          child: const Text('Numarasız devam et'),
        ),
      ],
    );
  }
}

/// "Adım 1/2" gibi küçük bir ilerleme rozeti.
class _StepBadge extends StatelessWidget {
  final int step;
  final int total;
  final String label;

  const _StepBadge({
    required this.step,
    required this.total,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'Adım $step/$total',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
