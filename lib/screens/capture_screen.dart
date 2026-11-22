import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/vehicle.dart';
import '../services/database_service.dart';
import '../services/plate_recognizer_service.dart';
import 'first_registration_screen.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final _picker = ImagePicker();

  // Model hazir oldugunda burayi gercek servis sinifiyla degistirin.
  final PlateRecognizerService _recognizer = MlKitPlateRecognizerService();

  final _plateController = TextEditingController();
  final _db = DatabaseService.instance;

  File? _imageFile;
  bool _isProcessing = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _recognizer.init();
  }

  @override
  void dispose() {
    _recognizer.dispose();
    _plateController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 90);
      if (picked == null) return;

      final file = File(picked.path);
      setState(() {
        _imageFile = file;
        _isProcessing = true;
      });

      final result = await _recognizer.recognize(file);

      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        final cleanedGuess = _db.normalizePlate(result.plateGuess);
        if (cleanedGuess.isNotEmpty) {
          _plateController.text = cleanedGuess;
          _plateController.selection = TextSelection.fromPosition(
            TextPosition(offset: cleanedGuess.length),
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Görüntü alınamadı: $e')),
      );
    }
  }

  Future<void> _continue() async {
    if (_isSubmitting) return;

    final plate = _db.normalizePlate(_plateController.text);
    if (plate.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen geçerli bir plaka girin.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final existingCustomer = await _db.findCustomerByPlate(plate);

      if (existingCustomer != null) {
        // Daimi musteri: QR veya telefon islemi yok, dogrudan kuyruga alinir.
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

      // Ilk kayit: QR / zorunlu telefon akisina gec.
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
                aspectRatio: 16 / 9,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: _imageFile == null
                      ? const Center(
                          child: Icon(
                            Icons.directions_car,
                            size: 64,
                            color: Colors.black26,
                          ),
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.file(_imageFile!, fit: BoxFit.cover),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Kamera'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Galeri'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (_isProcessing) const LinearProgressIndicator(),
              if (_isProcessing) const SizedBox(height: 12),
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
                  hintText: '34EDZ98',
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