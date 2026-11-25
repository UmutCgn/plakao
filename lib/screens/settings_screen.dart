import 'package:flutter/material.dart';

import '../models/price_preset.dart';
import '../services/messaging_service.dart';
import '../services/settings_service.dart';

/// Uygulama versiyonu ve yapımcı bilgisi. Ayarlar ekranının en altında
/// gösterilir.
const String kAppVersion = '2.0.0';
const String kAppMaker = 'UmutCgn';

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
  late bool _advancedTemplatesOn;
  late AppThemeMode _themeMode;
  late List<PricePreset> _pricePresets;
  late bool _waitWarningEnabled;
  late int _waitWarningMinutes;
  late bool _smartEstimateOn;
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
    _advancedTemplatesOn = current.advancedMessageTemplatesEnabled;
    _themeMode = current.themeMode;
    _pricePresets = List.of(current.pricePresets);
    _waitWarningEnabled = current.queueWaitWarningEnabled;
    _waitWarningMinutes = current.queueWaitWarningMinutes;
    _smartEstimateOn = current.smartWaitEstimateEnabled;
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
        advancedMessageTemplatesEnabled: _advancedTemplatesOn,
        shopLat: double.tryParse(_latController.text.trim()) ?? current.shopLat,
        shopLon: double.tryParse(_lonController.text.trim()) ?? current.shopLon,
        themeMode: _themeMode,
        pricePresets: _pricePresets,
        queueWaitWarningEnabled: _waitWarningEnabled,
        queueWaitWarningMinutes: _waitWarningMinutes,
        smartWaitEstimateEnabled: _smartEstimateOn,
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

  Future<void> _editPricePreset({PricePreset? existing, int? index}) async {
    final labelCtrl = TextEditingController(text: existing?.label ?? '');
    final priceCtrl =
        TextEditingController(text: existing != null ? existing.price.toStringAsFixed(0) : '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Yeni Ücret' : 'Ücreti Düzenle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelCtrl,
              decoration: const InputDecoration(labelText: 'Etiket (ör. SUV)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Ücret (₺)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kaydet')),
        ],
      ),
    );

    if (saved != true) return;
    final price = double.tryParse(priceCtrl.text.trim().replaceAll(',', '.'));
    if (labelCtrl.text.trim().isEmpty || price == null || price <= 0) return;

    setState(() {
      final preset = PricePreset(label: labelCtrl.text.trim(), price: price);
      if (index != null) {
        _pricePresets[index] = preset;
      } else {
        _pricePresets.add(preset);
      }
    });
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
            'Ücret Politikası',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Kuyruktaki "Ücret Belirle" butonunda görünecek hazır fiyatlar. '
            'Çoğu araç farklı ücrete yıkandığı için her araca kendi fiyatını '
            'ayrı ayrı atayabilirsiniz.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 10),
          ..._pricePresets.asMap().entries.map((e) {
            final i = e.key;
            final p = e.value;
            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                leading: const Icon(Icons.payments_outlined, color: Colors.indigo),
                title: Text(p.label),
                subtitle: Text('${p.price.toStringAsFixed(0)} ₺'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: () => _editPricePreset(existing: p, index: i),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                      onPressed: () => setState(() => _pricePresets.removeAt(i)),
                    ),
                  ],
                ),
              ),
            );
          }),
          OutlinedButton.icon(
            onPressed: () => _editPricePreset(),
            icon: const Icon(Icons.add),
            label: const Text('Yeni Ücret Ekle'),
          ),

          const SizedBox(height: 24),
          Text(
            'Araç Bekleme Süresi Uyarısı',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Açıkken, kuyrukta (yıkanıyor durumunda) belirlediğiniz süreden '
            'uzun bekleyen bir araç olursa telefonunuza bildirim gelir '
            '("araç uzun süredir bekliyor"). Her araç için sadece bir kez '
            'gönderilir.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Bekleme Uyarısını Aç'),
                    value: _waitWarningEnabled,
                    onChanged: (v) => setState(() => _waitWarningEnabled = v),
                  ),
                  if (_waitWarningEnabled) ...[
                    Row(
                      children: [
                        const Text('Eşik Süre:'),
                        Expanded(
                          child: Slider(
                            value: _waitWarningMinutes.toDouble(),
                            min: 5,
                            max: 120,
                            divisions: 23,
                            label: '$_waitWarningMinutes dk',
                            onChanged: (v) =>
                                setState(() => _waitWarningMinutes = v.round()),
                          ),
                        ),
                        SizedBox(
                          width: 54,
                          child: Text(
                            '$_waitWarningMinutes dk',
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),
          Text(
            'Görünüm',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          SegmentedButton<AppThemeMode>(
            segments: const [
              ButtonSegment(value: AppThemeMode.system, label: Text('Sistem'), icon: Icon(Icons.brightness_auto)),
              ButtonSegment(value: AppThemeMode.light, label: Text('Açık'), icon: Icon(Icons.light_mode)),
              ButtonSegment(value: AppThemeMode.dark, label: Text('Koyu'), icon: Icon(Icons.dark_mode)),
            ],
            selected: {_themeMode},
            onSelectionChanged: (s) => setState(() => _themeMode = s.first),
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
            'Yıkama tamamlandığında müşteriye giden mesajı burada hızlıca '
            'düzenleyebilirsiniz. Diğer (kuyruğa alındı / QR ilk temas) '
            'şablonlar ve etiketler Gelişmiş Ayarlar > Gelişmiş Mesaj '
            'Şablonları altındadır.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _readyController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Yıkama Tamamlandı Mesajı',
              prefixIcon: Icon(Icons.check_circle_outline),
            ),
          ),

          const SizedBox(height: 24),
          // Eşik/slider/deneysel gibi nadiren dokunulan, kafa karıştırıcı
          // ayarlar artık burada tek bir katlanabilir bölümde — ana ekran
          // sade kalsın diye varsayılan olarak kapalı.
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text(
                '⚙️ Gelişmiş Ayarlar',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'Plaka tanıma hassasiyeti, gelişmiş mesaj şablonları, deneysel özellik',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              childrenPadding: const EdgeInsets.only(bottom: 12),
              children: [
                const SizedBox(height: 4),
                Text(
                  'Plaka Tanıma',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
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

                const SizedBox(height: 16),
                Text(
                  'Gelişmiş Mesaj Şablonları (Deneysel)',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Gelişmiş Şablon Düzenleyiciyi Aç'),
                  subtitle: const Text(
                    'Açıkken QR ilk temas ve kuyruğa alındı mesajları için de '
                    'ham etiketli (【Plaka】, 【Kampanya Satırı】 vb.) serbest '
                    'düzenleme alanları burada belirir.',
                  ),
                  value: _advancedTemplatesOn,
                  onChanged: (v) => setState(() => _advancedTemplatesOn = v),
                ),
                if (_advancedTemplatesOn) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Aşağıdaki etiketlere dokunarak mesaja ekleyebilirsiniz:',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
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
                  const SizedBox(height: 16),
                  _tokenChips(_readyController),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _readyController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Yıkama Tamamlandı Mesajı (ham etiketli)',
                      prefixIcon: Icon(Icons.check_circle_outline),
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                Text(
                  'Deneysel Özellik',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('🧪 Akıllı Talep Tahmini'),
                  subtitle: const Text(
                    'Açıkken sol menüde bu özelliğe erişim belirir; hava '
                    'durumu + geçmiş verilere göre basit bir talep tahmini '
                    'sayfası açar. Kapatınca menü öğesi tamamen gizlenir.',
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
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true, signed: true),
                          decoration:
                              const InputDecoration(labelText: 'Dükkan Enlemi'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _lonController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true, signed: true),
                          decoration:
                              const InputDecoration(labelText: 'Dükkan Boylamı'),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('⏱️ Akıllı Bekleme Tahmini'),
                  subtitle: const Text(
                    'Açıkken her araç kartında, önündeki araç sayısı ve son '
                    'yıkamaların ortalama süresine göre hesaplanan tahmini '
                    'hazır olma saati ("Tahmini hazır: 14:35") gösterilir. '
                    'Müşteriye "ne zaman biter?" diye cevap vermek için '
                    'küçük ama pratik bir yardımcı.',
                  ),
                  value: _smartEstimateOn,
                  onChanged: (v) => setState(() => _smartEstimateOn = v),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _saving ? null : _saveSettings,
            icon: const Icon(Icons.save),
            label: Text(_saving ? 'Kaydediliyor...' : 'Ayarları Kaydet'),
          ),

          const SizedBox(height: 28),
          Center(
            child: Column(
              children: [
                Text(
                  'Plakao v$kAppVersion',
                  style: const TextStyle(fontSize: 12, color: Colors.black45),
                ),
                const SizedBox(height: 2),
                Text(
                  'Yapımcı: $kAppMaker',
                  style: const TextStyle(fontSize: 12, color: Colors.black45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}