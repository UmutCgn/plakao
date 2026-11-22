import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config/shop_config.dart';
import '../models/vehicle.dart';
import '../services/database_service.dart';
import '../services/messaging_service.dart';

enum _Step { qr, manualPhone }

/// Ilk kayit akisi:
/// 1) Once QR gosterilir (musteri kendi telefonuyla okutup hazir mesaji
///    dukkana gonderir, boylece numarasi dukkana duser).
/// 2) "QR Okumadi" secilirse telefon numarasi girisi ZORUNLU olur; numara
///    girilmeden kayit tamamlanmaz.
class FirstRegistrationScreen extends StatefulWidget {
  final String plate;

  const FirstRegistrationScreen({super.key, required this.plate});

  @override
  State<FirstRegistrationScreen> createState() =>
      _FirstRegistrationScreenState();
}

class _FirstRegistrationScreenState extends State<FirstRegistrationScreen> {
  _Step _step = _Step.qr;
  final _phoneController = TextEditingController();
  final _optionalPhoneController = TextEditingController();
  final _db = DatabaseService.instance;
  bool _saving = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _optionalPhoneController.dispose();
    super.dispose();
  }

  String get _qrPayload => MessagingService.buildWhatsAppUri(
        ShopConfig.shopWhatsAppNumber,
        ShopConfig.firstContactMessage(widget.plate),
      ).toString();

  Future<void> _finishFromQr() async {
    setState(() => _saving = true);
    final rawPhone = _optionalPhoneController.text.trim();

    if (rawPhone.isNotEmpty) {
      if (!MessagingService.isValidPhone(rawPhone)) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Geçerli bir telefon numarası girin.')),
        );
        return;
      }
      await _db.upsertCustomer(widget.plate, rawPhone);
    }

    await _db.addToQueue(
      plate: widget.plate,
      phone: rawPhone.isEmpty ? null : rawPhone,
      status: QueueStatus.inQueue,
    );

    if (mounted) {
      setState(() => _saving = false);
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _finishFromManualPhone() async {
    final rawPhone = _phoneController.text.trim();
    if (!MessagingService.isValidPhone(rawPhone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('QR okumayan ilk kayıtta geçerli telefon numarası zorunludur.'),
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

    // Dukkan sahibinin telefonundan musteriye hazir karsilama mesaji (WP -> SMS fallback).
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
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _step == _Step.qr ? _buildQrStep() : _buildManualStep(),
        ),
      ),
    );
  }

  Widget _buildQrStep() {
    return Column(
      children: [
        const Text(
          'Müşteriye QR kodu gösterin.\nKendi telefonuyla okutup açılan '
          'WhatsApp mesajını göndersin.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 20),
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
            size: 220,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _optionalPhoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Düşen numarayı şimdi gördüyseniz girin (opsiyonel)',
            hintText: '05xx xxx xx xx',
          ),
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _saving ? null : _finishFromQr,
            child: _saving
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Gönderildi, Kuyruğa Al'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: OutlinedButton(
            onPressed: _saving
                ? null
                : () => setState(() => _step = _Step.manualPhone),
            child: const Text('QR Okumadı (Telefon No Zorunlu)'),
          ),
        ),
      ],
    );
  }

  Widget _buildManualStep() {
    return Column(
      children: [
        const Text(
          'QR okutulamadı. İlk kayıt için müşterinin telefon numarasını girin.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _phoneController,
          autofocus: true,
          keyboardType: TextInputType.phone,
          style: const TextStyle(fontSize: 20),
          decoration: const InputDecoration(
            labelText: 'Telefon Numarası (zorunlu)',
            hintText: '05xx xxx xx xx',
          ),
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _saving ? null : _finishFromManualPhone,
            child: _saving
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Kaydet ve Mesaj Gönder'),
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _saving ? null : () => setState(() => _step = _Step.qr),
          child: const Text('QR Adımına Geri Dön'),
        ),
      ],
    );
  }
}