import 'dart:async';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:chatmcp/utils/color.dart';
import 'package:chatmcp/services/mojo_voice_service.dart';

class MojoVoicePanel extends StatefulWidget {
  final MojoVoiceService service;
  final VoidCallback onClose;
  final void Function(String transcript)? onTranscript;

  const MojoVoicePanel({
    super.key,
    required this.service,
    required this.onClose,
    this.onTranscript,
  });

  @override
  State<MojoVoicePanel> createState() => _MojoVoicePanelState();
}

class _MojoVoicePanelState extends State<MojoVoicePanel> with SingleTickerProviderStateMixin {
  MojoVoiceState _state = MojoVoiceState.idle;
  double _playbackProgress = 0.0;
  Duration _recordingDuration = Duration.zero;
  Duration _playbackDuration = Duration.zero;
  Timer? _recordingTimer;
  Timer? _playbackTimer;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  StreamSubscription? _stateSubscription;

  @override
  void initState() {
    super.initState();
    debugPrint('MoJoPanel: initState called');
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _stateSubscription = widget.service.stateStream.listen((state) {
      debugPrint('MoJoPanel: state changed to $state');
      setState(() => _state = state);
    });
  }

  @override
  void dispose() {
    debugPrint('MoJoPanel: disposing');
    _stateSubscription?.cancel();
    _recordingTimer?.cancel();
    _playbackTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final mins = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final ms = (d.inMilliseconds.remainder(1000) ~/ 10).toString().padLeft(2, '0');
    return '$mins:$secs.$ms';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.getLayoutBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(51),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          _buildStateIndicator(),
          const SizedBox(height: 12),
          _buildWaveform(),
          const SizedBox(height: 12),
          _buildDuration(),
          const SizedBox(height: 8),
          _buildStatusText(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(
          CupertinoIcons.waveform,
          color: AppColors.getThemeTextColor(context),
          size: 18,
        ),
        const SizedBox(width: 8),
        Text(
          'MoJo Voice',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.getThemeTextColor(context),
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: widget.onClose,
        child: Icon(
          CupertinoIcons.xmark_circle_fill,
          color: AppColors.getInactiveTextColor(context),
          size: 22,
        ),
        ),
      ],
    );
  }

  Widget _buildStateIndicator() {
    switch (_state) {
      case MojoVoiceState.recording:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.red.withAlpha((_pulseAnimation.value * 255).toInt()),
                    shape: BoxShape.circle,
                  ),
                );
              },
            ),
            const SizedBox(width: 8),
            Text(
              'Recording',
              style: TextStyle(
                fontSize: 13,
                color: Colors.red,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
      case MojoVoiceState.processing:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(
              'Processing',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.getThemeTextColor(context),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
      case MojoVoiceState.playing:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.speaker_2_fill,
              color: Theme.of(context).colorScheme.primary,
              size: 14,
            ),
            const SizedBox(width: 8),
            Text(
              'Playing reply',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
      case MojoVoiceState.error:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(CupertinoIcons.exclamationmark_circle, color: Colors.orange, size: 14),
            const SizedBox(width: 8),
            Text(
              'Error',
              style: TextStyle(
                fontSize: 13,
                color: Colors.orange,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
      case MojoVoiceState.idle:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.checkmark_circle,
              color: Colors.green,
              size: 14,
            ),
            const SizedBox(width: 8),
            Text(
              'Ready',
              style: TextStyle(
                fontSize: 13,
                color: Colors.green,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
    }
  }

  Widget _buildWaveform() {
    return SizedBox(
      height: 40,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return CustomPaint(
            painter: _WaveformPainter(
              state: _state,
              progress: _playbackProgress,
              animationValue: _pulseAnimation.value,
              textColor: AppColors.getThemeTextColor(context),
              accentColor: Theme.of(context).colorScheme.primary,
            ),
            size: const Size(double.infinity, 40),
          );
        },
      ),
    );
  }

  Widget _buildDuration() {
    final duration = _state == MojoVoiceState.recording
        ? _recordingDuration
        : _state == MojoVoiceState.playing
            ? _playbackDuration
            : Duration.zero;

    return Text(
      _formatDuration(duration),
      style: TextStyle(
        fontSize: 24,
        fontFamily: 'monospace',
        fontWeight: FontWeight.w300,
        color: AppColors.getThemeTextColor(context),
      ),
    );
  }

  Widget _buildStatusText() {
    String text;
    switch (_state) {
      case MojoVoiceState.recording:
        text = 'Speak now...';
        break;
      case MojoVoiceState.processing:
        text = 'Sending to MoJo Assistant...';
        break;
      case MojoVoiceState.playing:
        text = 'Transcript sent to chat';
        break;
      case MojoVoiceState.error:
        text = 'Try again';
        break;
      case MojoVoiceState.idle:
        text = 'Press mic to start';
        break;
    }

    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        color: AppColors.getInactiveTextColor(context),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final MojoVoiceState state;
  final double progress;
  final double animationValue;
  final Color textColor;
  final Color accentColor;

  _WaveformPainter({
    required this.state,
    required this.progress,
    required this.animationValue,
    required this.textColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final centerY = size.height / 2;
    final barCount = 25;
    final barSpacing = size.width / (barCount - 1);
    final random = Random(42);

    for (int i = 0; i < barCount; i++) {
      final x = i * barSpacing;
      double height;
      Color color;

      switch (state) {
        case MojoVoiceState.recording:
          height = (random.nextDouble() * 0.7 + 0.3) * size.height * animationValue;
          color = Colors.red.withAlpha((animationValue * 200).toInt());
          break;
        case MojoVoiceState.processing:
          height = size.height * 0.2;
          color = textColor.withAlpha(100);
          break;
        case MojoVoiceState.playing:
          final normalized = i / barCount;
          height = (random.nextDouble() * 0.5 + 0.2) * size.height;
          color = normalized <= progress ? accentColor : textColor.withAlpha(80);
          break;
        case MojoVoiceState.error:
          height = size.height * 0.15;
          color = Colors.orange.withAlpha(150);
          break;
        case MojoVoiceState.idle:
          height = size.height * 0.1;
          color = textColor.withAlpha(80);
          break;
      }

      paint.color = color;
      canvas.drawLine(
        Offset(x, centerY - height / 2),
        Offset(x, centerY + height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.state != state ||
        oldDelegate.progress != progress ||
        oldDelegate.animationValue != animationValue;
  }
}

class MojoVoicePanelOverlay {
  static OverlayEntry? _currentEntry;

  static void show({
    required BuildContext context,
    required MojoVoiceService service,
    void Function(String transcript)? onTranscript,
  }) {
    hide();

    _currentEntry = OverlayEntry(
      builder: (context) => Positioned(
        right: 20,
        bottom: 120,
        child: Material(
          color: Colors.transparent,
          child: MojoVoicePanel(
            service: service,
            onClose: hide,
            onTranscript: onTranscript,
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_currentEntry!);
  }

  static void hide() {
    _currentEntry?.remove();
    _currentEntry = null;
  }

  static void update() {
    _currentEntry?.markNeedsBuild();
  }
}