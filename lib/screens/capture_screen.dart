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

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _cameraReady = false;

  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;

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

  static const double _guideWidthRatio = 0.84;
  static const double _guideAspect = 3.6;

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
      final minZoom = await controller.getMinZoomLevel();
      final maxZoom = await controller.getMaxZoomLevel();

      if (!mounted) {
        controller.dispose();
        return;
      }

      final clampedMax = maxZoom > minZoom ? maxZoom : minZoom;
      final initialZoom = 1.0.clamp(minZoom, clampedMax);

      setState(() {
        _cameraController = controller;
        _minZoom = minZoom;
        _maxZoom = clampedMax;
        _currentZoom = initialZoom;
        _cameraReady = true;
      });

      await controller.setZoomLevel(initialZoom);
    } catch (e) {
      debugPrint('Kamera başlatılamadı: $e');
    }
  }

  Future<void> _setZoom(double zoom) async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    final target = zoom.clamp(_minZoom, _maxZoom);
    try {
      await controller.setZoomLevel(target);
      if (mounted) {
        setState(() => _currentZoom = target);
      }
    } catch (e) {
      debugPrint('Zoom ayarlanamadı: $e');
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
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
    );
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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Plaka Oku')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
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
                            width:
                                _cameraController!.value.previewSize?.height ??
                                    100,
                            height:
                                _cameraController!.value.previewSize?.width ??
                                    100,
                            child: CameraPreview(_cameraController!),
                          ),
                        )
                      else
                        const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white54,
                          ),
                        ),
                      if (_previewImage == null)
                        _ModernPlateGuideOverlay(
                          widthRatio: _guideWidthRatio,
                          aspectRatio: _guideAspect,
                        ),
                      if (_previewImage == null)
                        Positioned(
                          bottom: 14,
                          left: 24,
                          right: 24,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'Plakayı çerçeve içine hizalayın',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_isProcessing)
                        Container(
                          color: Colors.black45,
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (_previewImage == null &&
                  _cameraReady &&
                  _maxZoom > _minZoom) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.zoom_out,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    Expanded(
                      child: Slider(
                        value: _currentZoom.clamp(_minZoom, _maxZoom),
                        min: _minZoom,
                        max: _maxZoom,
                        onChanged: _setZoom,
                      ),
                    ),
                    SizedBox(
                      width: 42,
                      child: Text(
                        '${_currentZoom.toStringAsFixed(1)}x',
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [1.0, 2.0, 3.0]
                      .where((z) => z >= _minZoom && z <= _maxZoom)
                      .map(
                        (preset) => ChoiceChip(
                          visualDensity: VisualDensity.compact,
                          label: Text('${preset.toStringAsFixed(0)}x'),
                          selected: (_currentZoom - preset).abs() < 0.15,
                          onSelected: (_) => _setZoom(preset),
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 56,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton.outlined(
                          onPressed: _isProcessing ? null : _pickFromGallery,
                          icon: const Icon(Icons.photo_library_outlined),
                          iconSize: 20,
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Galeriden Seç',
                        ),
                        const Text(
                          'Galeri',
                          style: TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  GestureDetector(
                    onTap: (_isProcessing || _previewImage != null)
                        ? null
                        : _capture,
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (_isProcessing || _previewImage != null)
                            ? Colors.grey
                            : colorScheme.primary,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: _isProcessing
                          ? const Padding(
                              padding: EdgeInsets.all(15),
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 24,
                            ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  const SizedBox(width: 56),
                ],
              ),
              if (_previewImage != null)
                TextButton.icon(
                  onPressed: _isProcessing ? null : _retake,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Tekrar Çek'),
                ),
              const SizedBox(height: 10),
              TextField(
                controller: _plateController,
                textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
                decoration: const InputDecoration(
                  labelText: 'Plaka (düzenlenebilir)',
                  hintText: '34 EDZ 98',
                ),
                onSubmitted: (_) => _continue(),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
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

class _ModernPlateGuideOverlay extends StatelessWidget {
  final double widthRatio;
  final double aspectRatio;

  const _ModernPlateGuideOverlay({
    required this.widthRatio,
    required this.aspectRatio,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxWidth = constraints.maxWidth * widthRatio;
        final boxHeight = (boxWidth / aspectRatio).clamp(
          44.0,
          constraints.maxHeight * 0.45,
        );

        return Center(
          child: SizedBox(
            width: boxWidth,
            height: boxHeight,
            child: CustomPaint(
              painter: _CornerBracketsPainter(
                color: Colors.amberAccent,
                strokeWidth: 3.0,
                bracketLength: 18.0,
                radius: 10.0,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CornerBracketsPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double bracketLength;
  final double radius;

  const _CornerBracketsPainter({
    required this.color,
    required this.strokeWidth,
    required this.bracketLength,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(radius),
      ),
      fillPaint,
    );

    final borderPaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;
    final len = mathMin(bracketLength, mathMin(w, h) * 0.45);
    final r = mathMin(radius, len * 0.6);

    // Sol üst
    canvas.drawPath(
      Path()
        ..moveTo(0, len)
        ..lineTo(0, r)
        ..quadraticBezierTo(0, 0, r, 0)
        ..lineTo(len, 0),
      borderPaint,
    );

    // Sağ üst
    canvas.drawPath(
      Path()
        ..moveTo(w - len, 0)
        ..lineTo(w - r, 0)
        ..quadraticBezierTo(w, 0, w, r)
        ..lineTo(w, len),
      borderPaint,
    );

    // Sağ alt
    canvas.drawPath(
      Path()
        ..moveTo(w, h - len)
        ..lineTo(w, h - r)
        ..quadraticBezierTo(w, h, w - r, h)
        ..lineTo(w - len, h),
      borderPaint,
    );

    // Sol alt
    canvas.drawPath(
      Path()
        ..moveTo(len, h)
        ..lineTo(r, h)
        ..quadraticBezierTo(0, h, 0, h - r)
        ..lineTo(0, h - len),
      borderPaint,
    );
  }

  double mathMin(double a, double b) => a < b ? a : b;

  @override
  bool shouldRepaint(covariant _CornerBracketsPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.bracketLength != bracketLength ||
        oldDelegate.radius != radius;
  }
}