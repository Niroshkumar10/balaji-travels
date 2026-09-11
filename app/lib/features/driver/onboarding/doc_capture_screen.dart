import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/common_widgets.dart';

/// Shared "capture a document" flow — an illustration/dropzone +
/// requirements, then a review step with Retake / Use photo. Reused for the
/// driving licence, profile photo, identity document, vehicle RC, and
/// insurance steps in the onboarding checklist.
///
/// Two illustration styles match the reference exactly: a pink circular
/// icon for Driving Licence / Profile Photo ([dashedDropzone] false), and a
/// dashed-border dropzone card for Aadhaar / Vehicle RC / Insurance
/// ([dashedDropzone] true). Profile Photo is also the one screen whose
/// primary action IS the camera with a single "Choose photo" link below
/// ([primaryOpensCamera] true); everything else leads with an "Upload …"
/// action (gallery-first) plus an explicit "Take photo | Choose from
/// gallery" link row.
///
/// The picked image is shown for review only — see DriverOnboardingStore for
/// why it isn't kept afterward. Pops `true` once the rider confirms "Use
/// photo", `null`/`false` otherwise.
class DocCaptureScreen extends StatefulWidget {
  const DocCaptureScreen({
    super.key,
    required this.title,
    required this.requirements,
    this.heading,
    this.description,
    this.uploadLabel = 'Upload',
    this.reviewPrompt = 'Is the information clear?',
    this.circular = false,
    this.dashedDropzone = false,
    this.primaryOpensCamera = false,
  });

  final String title;
  final List<String> requirements;

  /// Repeated below the app bar as a heading (Aadhaar/RC/Insurance style).
  /// Leave null for the plain-illustration screens, which don't repeat one.
  final String? heading;

  /// Shown under the illustration (Driving Licence style). Ignored if
  /// [heading] is set instead.
  final String? description;

  final String uploadLabel;
  final String reviewPrompt;
  final bool circular;
  final bool dashedDropzone;
  final bool primaryOpensCamera;

  @override
  State<DocCaptureScreen> createState() => _DocCaptureScreenState();
}

class _DocCaptureScreenState extends State<DocCaptureScreen> {
  Uint8List? _bytes;
  bool _busy = false;

  Future<void> _pick(ImageSource source) async {
    setState(() => _busy = true);
    try {
      final file = await ImagePicker().pickImage(source: source, imageQuality: 85);
      if (file != null) {
        final bytes = await file.readAsBytes();
        if (mounted) setState(() => _bytes = bytes);
      }
    } catch (_) {
      // Camera unavailable (common on desktop/web) — fall back to gallery
      // silently rather than dead-ending the flow with an error.
      if (source == ImageSource.camera && mounted) await _pick(ImageSource.gallery);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: LoadingOverlay(
        busy: _busy,
        child: _bytes == null ? _requirementsView() : _reviewView(),
      ),
    );
  }

  Widget _illustration() {
    if (widget.dashedDropzone) {
      return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _pick(ImageSource.gallery),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 36),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.line, style: BorderStyle.solid),
          ),
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: AppColors.cardSelectedBackground, shape: BoxShape.circle),
                child: const Icon(Icons.upload_rounded, color: AppColors.primary),
              ),
              const SizedBox(height: 14),
              const Text('Tap to add document', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text('JPG or PNG · Max 10 MB', style: TextStyle(color: AppColors.inkSoft, fontSize: 12)),
            ],
          ),
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(color: AppColors.cardSelectedBackground, borderRadius: BorderRadius.circular(20)),
      child: Center(
        child: widget.circular
            ? const Icon(Icons.no_photography_outlined, size: 56, color: AppColors.primary)
            : Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.badge_outlined, color: AppColors.primary, size: 30),
              ),
      ),
    );
  }

  Widget _requirementsView() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (widget.heading != null) ...[
          Text(widget.heading!, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          if (widget.description != null) ...[
            const SizedBox(height: 6),
            Text(widget.description!, style: const TextStyle(color: AppColors.inkSoft)),
          ],
          const SizedBox(height: 18),
        ],
        _illustration(),
        if (widget.heading == null && widget.description != null) ...[
          const SizedBox(height: 16),
          Text(widget.description!, style: const TextStyle(color: AppColors.inkSoft)),
        ],
        const SizedBox(height: 20),
        const Text('Requirements', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 10),
        ...widget.requirements.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.success),
                  const SizedBox(width: 10),
                  Expanded(child: Text(r, style: const TextStyle(fontSize: 13.5))),
                ],
              ),
            )),
        const SizedBox(height: 28),
        PrimaryButton(
          label: widget.uploadLabel,
          onPressed: () => _pick(widget.primaryOpensCamera ? ImageSource.camera : ImageSource.gallery),
        ),
        const SizedBox(height: 12),
        widget.primaryOpensCamera
            ? Center(
                child: TextButton(onPressed: () => _pick(ImageSource.gallery), child: const Text('Choose photo')),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(onPressed: () => _pick(ImageSource.camera), child: const Text('Take photo')),
                  const SizedBox(width: 16),
                  TextButton(onPressed: () => _pick(ImageSource.gallery), child: const Text('Choose from gallery')),
                ],
              ),
      ],
    );
  }

  Widget _reviewView() {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: widget.circular
                ? CircleAvatar(radius: 90, backgroundImage: MemoryImage(_bytes!))
                : Padding(
                    padding: const EdgeInsets.all(20),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.memory(_bytes!, fit: BoxFit.contain),
                    ),
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.reviewPrompt, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.inkSoft)),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _bytes = null),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      child: const Text('Retake'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.success, minimumSize: const Size.fromHeight(52)),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Use photo'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
