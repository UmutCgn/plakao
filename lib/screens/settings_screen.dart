import 'package:flutter/material.dart';

import '../services/messaging_service.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _shopNameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _firstContactController;
  late final TextEditingController _welcomeController;
  late final TextEditingController _readyController;
  late double _confThreshold;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final current = SettingsService.instance.current;
    _shopNameController = TextEditingController(text: current.shopName);
    _phoneController = TextEditingController(text: current.ownerPhone);
    _firstContactController =
        TextEditingController(text: current.firstContactTemplate);
    _welcomeController = TextEditingController(text: current.welcomeTemplate);
    _readyController = TextEditingController(text: current.messageTemplate);
    _confThreshold = current.plateConfThreshold;
  }

  @override
  void dispose() {
    _shopNameController.dispose();
    _phoneController.dispose();
    _firstContactController.dispose();
    _welcomeController.dispose();
    _readyController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    final rawPhone = _phoneController.text.trim();
    final normalizedPhone = AppSettings.normalizeTrPhone(rawPhone);
    if (rawPhone.isNotEmpty && normalizedPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Geçerli 10 haneli bir cep numarası girin (örn. 05xx xxx xx xx).',
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final current = SettingsService.instance.current;
    await SettingsService.instance.save(
      current.copyWith(
        shopName: _shopNameController.text,
        ownerPhone: normalizedPhone,
        firstContactTemplate: _firstContactController.text,
        welcomeTemplate: _welcomeController.text,
        messageTemplate: _readyController.text,
        plateConfThreshold: _confThreshold,
      ),
    );

    if (!mounted) return;
    setState(() {
      _saving = false;
      _phoneController.text = SettingsService.instance.current.ownerPhone;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ayarlar kaydedildi.')),
    );
    Navigator.of(context).pop(true);
  }

  Future<void> _sendTestMessage() async {
    final normalized = AppSettings.normalizeTrPhone(_phoneController.text);
    if (normalized.isEmpty || !MessagingService.isValidPhone(normalized)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Önce geçerli bir telefon numarası girin.'),
        ),
      );
      return;
    }

    final preview = _readyController.text
        .replaceAll('{plate}', '34ABC123')
        .replaceAll('{shop}', _shopNameController.text.trim())
        .replaceAll('{campaign}', SettingsService.instance.current.activeCampaign)
        .replaceAll(
          '{campaignLine}',
          SettingsService.instance.current.activeCampaign.trim().isNotEmpty
              ? '\nKampanya: ${SettingsService.instance.current.activeCampaign.trim()}'
              : '',
        );

    final ok = await MessagingService.sendWhatsAppOrSms(normalized, preview);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mesaj uygulaması açılamadı.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dükkan Ayarları'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'İşletme ve İletişim',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _shopNameController,
            decoration: const InputDecoration(
              labelText: 'Dükkan Adı',
              prefixIcon: Icon(Icons.local_car_wash),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Dükkan WhatsApp / SMS Numarası',
              hintText: '05xx xxx xx xx veya 905xxxxxxxxx',
              helperText: '905xxxxxxxxx formatında kaydedilir.',
              prefixIcon: Icon(Icons.phone),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _sendTestMessage,
            icon: const Icon(Icons.send),
            label: const Text('Bu Numaraya Test Mesajı Gönder'),
          ),
          const SizedBox(height: 24),
          Text(
            'Hazır Mesaj Şablonları',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Etiketler: {plate}, {shop}, {campaign}, {campaignLine}',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _readyController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Yıkama Tamamlandı Mesajı',
              prefixIcon: Icon(Icons.check_circle_outline),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _welcomeController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Kuyruğa Alındı (Hoş Geldiniz) Mesajı',
              prefixIcon: Icon(Icons.waving_hand_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _firstContactController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'QR İlk Temas Mesajı',
              prefixIcon: Icon(Icons.qr_code),
            ),
          ),
          const SizedBox(height: 24),
          
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _saving ? null : _saveSettings,
            icon: const Icon(Icons.save),
            label: Text(_saving ? 'Kaydediliyor...' : 'Ayarları Kaydet'),
          ),
        ],
      ),
    );
  }
}