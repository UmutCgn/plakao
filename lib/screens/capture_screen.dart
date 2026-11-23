import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../models/vehicle.dart';
import '../services/database_service.dart';
import '../services/plate_recognizer_service.dart';
import '../services/settings_service.dart';
import 'first_registration_screen.dart';

/// Plaka okuma ekranı. Artık `image_picker` ile native kamera uygulamasını
/// tam ekran açmak yerine `camera` paketiyle CANLI ÖNİZLEME gösterir ve
/// ortada sabit bir rehber dikdörtgeni çizer. Kullanıcı plakayı bu
/// dikdörtgenin içine hizalayıp çeker; biz de fotoğrafı TAM OLARAK bu
/// dikdörtgenin oranına göre kırpıp 3x büyüterek OCR'a göndeririz. Bu,
/// "rastgele yazılar okunuyor" sorununun en büyük kaynağı olan "tüm kare
/// OCR'dan geçiyor" problemini çözer.
///
/// Galeri'den seçilen fotoğraflarda rehber dikdörtgeni olmadığı için tam
/// kare OCR + format regex filtresiyle okunur (PlateRecognizerService zaten
/// bunu strictFormat ile yapıyor).
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _cameraReady = false;

  final _picker = ImagePicker();
  late final PlateRecognizerService _recognizer = TFLitePlateRecognizerService(
    confidenceThreshold: SettingsService.instance.current.plateConfThreshold,
    strictFormat: SettingsService.instance.current.strictPlateFormat,
  );

  final _plateController = TextEditingController();
  final _db = DatabaseService.instance;

  File? _previewImage;
  bool _isProcessing = false;
  bool _isSubmitting = false;

  // Rehber (ekrandaki kılavuz) dikdörtgeni: Türk plakası en/boy oranı ~4.6:1
  static const double _guideWidthRatio = 0.82;
  static const double _guideAspect = 4.6;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recognizer.init();
    _setupCamera();
  }

  Future<void> _setupCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final backCam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        backCam,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _cameraController = controller;
        _cameraReady = true;
      });
    } catch (e) {
      debugPrint('Kamera başlatılamadı: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      setState(() {
        _cameraController = null;
        _cameraReady = false;
      });
    } else if (state == AppLifecycleState.resumed) {
      _setupCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _recognizer.dispose();
    _plateController.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized || _isProcessing) {
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final shot = await controller.takePicture();
      final cropped = await _cropToGuide(File(shot.path));
      await _runOcr(cropped);
    } catch (e) {
      debugPrint('Çekim hatası: $e');
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// Ekrandaki rehber dikdörtgeninin oranını kullanarak çekilen fotoğrafı
  /// kırpar ve 3x büyütür. NOT: Bazı cihazlarda kamera sensör döndürmesi
  /// farklı davranabilir; sonuç ekrandaki kılavuzla tam örtüşmezse
  /// `_guideWidthRatio` / `_guideAspect` değerlerini cihaza göre ince ayar
  /// yapın. Kırpma başarısız olsa bile OCR tam kare üzerinde + format
  /// regex'iyle çalışmaya devam eder (akış kilitlenmez).
  Future<File> _cropToGuide(File original) async {
    try {
      final bytes = await original.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return original;

      final guideW = (decoded.width * _guideWidthRatio).round();
      final guideH = (guideW / _guideAspect).round();
      final x = ((decoded.width - guideW) / 2).round();
      final y = ((decoded.height - guideH) / 2).round();

      final cropped = img.copyCrop(
        decoded,
        x: x.clamp(0, decoded.width - 1),
        y: y.clamp(0, decoded.height - 1),
        width: guideW.clamp(1, decoded.width),
        height: guideH.clamp(1, decoded.height),
      );
      final upscaled = img.copyResize(cropped, width: cropped.width * 3);

      final outFile = File('${original.path}_crop.jpg');
      await outFile.writeAsBytes(img.encodeJpg(upscaled, quality: 95));
      return outFile;
    } catch (e) {
      debugPrint('Kırpma hatası, orijinal kare kullanılıyor: $e');
      return original;
    }
  }

  Future<void> _pickFromGallery() async {
    final picked =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
    if (picked == null) return;
    setState(() => _isProcessing = true);
    await _runOcr(File(picked.path));
  }

  Future<void> _runOcr(File imageFile) async {
    setState(() => _previewImage = imageFile);
    final result = await _recognizer.recognize(imageFile);
    if (!mounted) return;
    setState(() {
      _isProcessing = false;
      if (result.plateGuess.isNotEmpty) {
        _plateController.text = result.plateGuess;
        _plateController.selection = TextSelection.fromPosition(
          TextPosition(offset: result.plateGuess.length),
        );
      }
    });
  }

  void _retake() {
    setState(() {
      _previewImage = null;
      _plateController.clear();
    });
  }

  Future<void> _continue() async {
    if (_isSubmitting) return;

    final plate = _db.normalizePlate(_plateController.text);
    if (plate.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen geçerli bir plaka girin.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final existingCustomer = await _db.findCustomerByPlate(plate);

      if (existingCustomer != null) {
        await _db.addToQueue(
          plate: plate,
          phone: existingCustomer.phone,
          status: QueueStatus.inQueue,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$plate (Daimi müşteri) doğrudan kuyruğa alındı.'),
          ),
        );
        Navigator.of(context).pop(true);
        return;
      }

      if (!mounted) return;
      final added = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => FirstRegistrationScreen(plate: plate),
        ),
      );
      if (added == true && mounted) {
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plaka Oku')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: Colors.black),
                      if (_previewImage != null)
                        Image.file(_previewImage!, fit: BoxFit.cover)
                      else if (_cameraReady && _cameraController != null)
                        FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: _cameraController!.value.previewSize?.height ?? 100,
                            height: _cameraController!.value.previewSize?.width ?? 100,
                            child: CameraPreview(_cameraController!),
                          ),
                        )
                      else
                        const Center(
                          child: CircularProgressIndicator(color: Colors.white54),
                        ),
                      if (_previewImage == null)
                        Center(
                          child: FractionallySizedBox(
                            widthFactor: _guideWidthRatio,
                            heightFactor:
                                (_guideWidthRatio / _guideAspect) * (3 / 4),
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.amberAccent,
                                  width: 3,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      if (_previewImage == null)
                        const Positioned(
                          bottom: 10,
                          left: 0,
                          right: 0,
                          child: Text(
                            'Plakayı çerçeve içine hizalayın',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                            ),
                          ),
                        ),
                      if (_isProcessing)
                        Container(
                          color: Colors.black45,
                          child: const Center(
                            child: CircularProgressIndicator(color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (_isProcessing || _previewImage != null)
                          ? null
                          : _capture,
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Çek & Oku'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isProcessing ? null : _pickFromGallery,
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Galeri'),
                    ),
                  ),
                ],
              ),
              if (_previewImage != null)
                TextButton.icon(
                  onPressed: _isProcessing ? null : _retake,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tekrar Çek'),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _plateController,
                textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
                decoration: const InputDecoration(
                  labelText: 'Plaka (düzenlenebilir)',
                  hintText: '34 EDZ 98',
                ),
                onSubmitted: (_) => _continue(),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _continue,
                  child: const Text('Devam Et'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
