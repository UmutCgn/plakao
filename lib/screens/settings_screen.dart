import 'package:flutter/material.dart';

import '../services/messaging_service.dart';
import '../services/settings_service.dart';

/// Mesaj şablonlarının içindeki {plate} / {shop} / {campaignLine} gibi
/// kod-benzeri parantezli etiketler, dükkan sahibi için kafa karıştırıcıydı.
/// Burada depolama formatı (ShopConfig._render içinde kullanılan {plate} vb.)
/// AYNI KALIYOR; sadece EKRANDA gösterilen/düzenlenen metin, köşeli
/// süslü parantez içermeyen "dost" jetonlara çevriliyor ve kaydedilirken
/// geri çevriliyor. Kullanıcı hiçbir zaman {} görmüyor.
const Map<String, String> _tokenToFriendly = {
  '{plate}': '【Plaka】',
  '{shop}': '【Dükkan Adı】',
  '{campaign}': '【Kampanya Metni】',
  '{campaignLine}': '【Kampanya Satırı】',
};

String _toFriendly(String raw) {
  var out = raw;
  _tokenToFriendly.forEach((token, friendly) => out = out.replaceAll(token, friendly));
  return out;
}

String _toRaw(String friendly) {
  var out = friendly;
  _tokenToFriendly.forEach((token, friendlyTok) => out = out.replaceAll(friendlyTok, token));
  return out;
}

void _insertAtCursor(TextEditingController c, String text) {
  final sel = c.selection;
  final start = sel.start < 0 ? c.text.length : sel.start;
  final end = sel.end < 0 ? c.text.length : sel.end;
  final newText = c.text.replaceRange(start, end, text);
  c.text = newText;
  c.selection = TextSelection.collapsed(offset: start + text.length);
}

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
  late final TextEditingController _latController;
  late final TextEditingController _lonController;

  late double _confThreshold;
  late bool _strictFormat;
  late bool _experimentalOn;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final current = SettingsService.instance.current;
    _shopNameController = TextEditingController(text: current.shopName);
    _phoneController = TextEditingController(text: current.ownerPhone);
    _firstContactController =
        TextEditingController(text: _toFriendly(current.firstContactTemplate));
    _welcomeController =
        TextEditingController(text: _toFriendly(current.welcomeTemplate));
    _readyController =
        TextEditingController(text: _toFriendly(current.messageTemplate));
    _latController = TextEditingController(text: current.shopLat.toString());
    _lonController = TextEditingController(text: current.shopLon.toString());
    _confThreshold = current.plateConfThreshold;
    _strictFormat = current.strictPlateFormat;
    _experimentalOn = current.experimentalFeatureEnabled;
  }

  @override
  void dispose() {
    _shopNameController.dispose();
    _phoneController.dispose();
    _firstContactController.dispose();
    _welcomeController.dispose();
    _readyController.dispose();
    _latController.dispose();
    _lonController.dispose();
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
        firstContactTemplate: _toRaw(_firstContactController.text),
        welcomeTemplate: _toRaw(_welcomeController.text),
        messageTemplate: _toRaw(_readyController.text),
        plateConfThreshold: _confThreshold,
        strictPlateFormat: _strictFormat,
        experimentalFeatureEnabled: _experimentalOn,
        shopLat: double.tryParse(_latController.text.trim()) ?? current.shopLat,
        shopLon: double.tryParse(_lonController.text.trim()) ?? current.shopLon,
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
        const SnackBar(content: Text('Önce geçerli bir telefon numarası girin.')),
      );
      return;
    }

    final rawTpl = _toRaw(_readyController.text);
    final preview = rawTpl
        .replaceAll('{plate}', '34ABC123')
        .replaceAll('{shop}', _shopNameController.text.trim())
        .replaceAll('{campaign}', 'Örnek Kampanya')
        .replaceAll('{campaignLine}', '\nKampanya: Örnek Kampanya');

    final ok = await MessagingService.sendWhatsAppOrSms(normalized, preview);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mesaj uygulaması açılamadı.')),
      );
    }
  }

  Widget _tokenChips(TextEditingController controller) {
    return Wrap(
      spacing: 6,
      runSpacing: -6,
      children: _tokenToFriendly.values.map((friendly) {
        return ActionChip(
          label: Text(friendly, style: const TextStyle(fontSize: 12)),
          onPressed: () => setState(() => _insertAtCursor(controller, friendly)),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dükkan Ayarları')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'İşletme ve İletişim',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
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
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Aşağıdaki etiketlere dokunarak mesaja ekleyebilirsiniz:',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 10),

          _tokenChips(_readyController),
          const SizedBox(height: 8),
          TextField(
            controller: _readyController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Yıkama Tamamlandı Mesajı',
              prefixIcon: Icon(Icons.check_circle_outline),
            ),
          ),
          const SizedBox(height: 16),

          _tokenChips(_welcomeController),
          const SizedBox(height: 8),
          TextField(
            controller: _welcomeController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Kuyruğa Alındı (Hoş Geldiniz) Mesajı',
              prefixIcon: Icon(Icons.waving_hand_outlined),
            ),
          ),
          const SizedBox(height: 16),

          _tokenChips(_firstContactController),
          const SizedBox(height: 8),
          TextField(
            controller: _firstContactController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'QR İlk Temas Mesajı',
              prefixIcon: Icon(Icons.qr_code),
            ),
          ),

          const SizedBox(height: 24),
          Text(
            'Plaka Tanıma',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Model TFLite formatına geçtiğinde burada hiçbir şeyi '
            'değiştirmeniz gerekmez — eşik ve format kuralı otomatik '
            'uygulanır (bkz. plate_recognizer_service.dart).',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('Güven Eşiği:'),
              Expanded(
                child: Slider(
                  value: _confThreshold,
                  min: 0.05,
                  max: 0.90,
                  divisions: 17,
                  label: _confThreshold.toStringAsFixed(2),
                  onChanged: (v) => setState(() => _confThreshold = v),
                ),
              ),
              Text(_confThreshold.toStringAsFixed(2)),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Sıkı Format Kontrolü'),
            subtitle: const Text(
              'Açıkken sadece "İL KODU + HARF + SAYI" formatına uyan '
              'sonuçlar plaka alanına yazılır (önerilir).',
            ),
            value: _strictFormat,
            onChanged: (v) => setState(() => _strictFormat = v),
          ),

          const SizedBox(height: 24),
          Text(
            'Deneysel Özellik',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('🧪 Akıllı Talep Tahmini'),
            subtitle: const Text(
              'Açıkken ana ekranın sağ üstünde ⋮ menüsü belirir ve hava '
              'durumu + geçmiş verilere göre basit bir talep tahmini sayfası '
              'açar. Kapatınca menü tamamen gizlenir.',
            ),
            value: _experimentalOn,
            onChanged: (v) => setState(() => _experimentalOn = v),
          ),
          if (_experimentalOn) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _latController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(labelText: 'Dükkan Enlemi'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _lonController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(labelText: 'Dükkan Boylamı'),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 24),
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
