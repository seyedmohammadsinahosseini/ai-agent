import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../theme.dart';

/// Voice-to-text DEMO button.
///
/// This is intentionally a UI-only mock for now (no microphone permission or
/// real audio capture): tapping shows a recording animation for a few
/// seconds, then inserts a clearly-labeled placeholder transcript into the
/// input box. This lets us validate the interaction/flow while a proper
/// Speech-to-Text provider is chosen later - swapping in real audio capture +
/// STT only requires replacing `_simulateRecording()` below.
class VoiceInputButton extends StatefulWidget {
  final ValueChanged<String> onTranscribed;
  const VoiceInputButton({super.key, required this.onTranscribed});

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton> with SingleTickerProviderStateMixin {
  bool _recording = false;
  int _seconds = 0;
  Timer? _timer;
  late final AnimationController _pulseController;

  static const List<String> _demoTranscripts = [
    "List the files in this folder and tell me which ones are largest.",
    "Clean up temporary files older than 30 days.",
    "Rename old_report.csv to report_2026.csv.",
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _toggleRecording() {
    if (_recording) {
      _stopAndTranscribe();
      return;
    }
    setState(() {
      _recording = true;
      _seconds = 0;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _seconds++);
      if (_seconds >= 4) _stopAndTranscribe();
    });
  }

  void _stopAndTranscribe() {
    _timer?.cancel();
    if (!_recording) return;
    setState(() => _recording = false);
    final demoText = _demoTranscripts[Random().nextInt(_demoTranscripts.length)];
    widget.onTranscribed(demoText);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Demo transcript inserted - real speech-to-text coming soon.'),
        duration: Duration(seconds: 2),
        backgroundColor: AppColors.surfaceHighlight,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _recording ? 'Stop recording (demo)' : 'Voice input (demo)',
      child: GestureDetector(
        onTap: _toggleRecording,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _recording ? AppColors.blocked.withValues(alpha: 0.16) : AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _recording ? AppColors.blocked : AppColors.border),
          ),
          child: _recording
              ? Stack(
                  alignment: Alignment.center,
                  children: [
                    ScaleTransition(
                      scale: Tween(begin: 0.9, end: 1.25).animate(
                        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
                      ),
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: const BoxDecoration(color: AppColors.blocked, shape: BoxShape.circle),
                      ),
                    ),
                    Positioned(
                      bottom: 2,
                      child: Text('${_seconds}s',
                          style: const TextStyle(fontSize: 8, color: AppColors.blocked, fontWeight: FontWeight.bold)),
                    ),
                  ],
                )
              : const Icon(Icons.mic_none_rounded, size: 18, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
