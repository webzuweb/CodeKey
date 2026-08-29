import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'app_logger.dart';
import 'localization.dart';
import 'theme.dart';

class InstantCameraPage extends StatefulWidget {
  const InstantCameraPage({super.key});

  @override
  State<InstantCameraPage> createState() => _InstantCameraPageState();
}

class _InstantCameraPageState extends State<InstantCameraPage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _initializing = true;
  bool _capturing = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('no_camera_available');
      final back = cameras.where((c) => c.lensDirection == CameraLensDirection.back);
      final camera = back.isNotEmpty ? back.first : cameras.first;
      final controller = CameraController(
        camera,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      AppLogger.instance.info('camera.inline_ready', {
        'name': camera.name,
        'lensDirection': camera.lensDirection.name,
      });
      setState(() => _initializing = false);
    } on Object catch (e, st) {
      AppLogger.instance.error('camera.inline_init_failed', e, stackTrace: st);
      if (mounted) setState(() { _error = e; _initializing = false; });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      unawaited(c.dispose());
      _controller = null;
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      setState(() => _initializing = true);
      unawaited(_initialize());
    }
  }

  Future<void> _takePicture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    try {
      AppLogger.instance.info('camera.inline_capture_started');
      final file = await c.takePicture();
      AppLogger.instance.info('camera.inline_capture_completed', {'extension': '.jpg'});
      if (!mounted) return;
      Navigator.of(context).pop(file);
    } on Object catch (e, st) {
      AppLogger.instance.error('camera.inline_capture_failed', e, stackTrace: st);
      if (mounted) {
        setState(() { _capturing = false; _error = e; });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_controller != null && _controller!.value.isInitialized)
              Center(child: CameraPreview(_controller!))
            else
              Center(
                child: _initializing
                    ? const CircularProgressIndicator()
                    : Text(
                        _error == null ? strings.t('cameraUnavailable') : strings.t('cameraOpenFailed'),
                        style: const TextStyle(color: Colors.white70),
                      ),
              ),
            Positioned(
              left: 14,
              top: 10,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Center(
                child: GestureDetector(
                  onTap: _capturing ? null : _takePicture,
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 5),
                      color: _capturing ? CodeKeyTheme.muted : Colors.white24,
                    ),
                    child: _capturing
                        ? const Padding(
                            padding: EdgeInsets.all(22),
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 34),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
