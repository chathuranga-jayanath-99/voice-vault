import 'package:flutter/material.dart';

/// Static amplitude peaks with a moving playhead gradient.
///
/// Renders N bars whose heights are scaled by [peaks] (each value 0.0–1.0).
/// A horizontal gradient sweeps a [playedColor] ← transparent mask across the
/// row so the playhead appears to fill the played portion.
///
/// Widget cost is O(N) regardless of progress — no per-bar color switches.
class WaveformBar extends StatelessWidget {
  final List<double> peaks;
  final double progress;
  final Color playedColor;
  final Color idleColor;

  const WaveformBar({
    super.key,
    required this.peaks,
    required this.progress,
    this.playedColor = const Color(0xFFE53935),
    this.idleColor = const Color(0xFF3A3A3A),
  });

  @override
  Widget build(BuildContext context) {
    if (peaks.isEmpty) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
      child: SizedBox(
        height: 28,
        child: LayoutBuilder(
          builder: (ctx, c) {
            final played = (progress.clamp(0.0, 1.0)) * c.maxWidth;
            return Stack(
              children: [
                _Bars(peaks: peaks, color: idleColor),
                // Painted-on gradient sweep: bars behind turn red up to `played`,
                // fade to transparent afterwards.
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: played,
                  child: ShaderMask(
                    shaderCallback: (rect) => const LinearGradient(
                      colors: [Colors.white, Colors.white],
                    ).createShader(rect),
                    blendMode: BlendMode.srcIn,
                    child: _Bars(peaks: peaks, color: idleColor),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Bars extends StatelessWidget {
  final List<double> peaks;
  final Color color;
  const _Bars({required this.peaks, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final p in peaks)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0.5),
              child: _Bar(height: p, color: color),
            ),
          ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  final double height;
  final Color color;
  const _Bar({required this.height, required this.color});

  @override
  Widget build(BuildContext context) {
    // Map 0.0–1.0 to 2–24 px so silent regions still show a faint bar.
    final h = 2.0 + 22.0 * height.clamp(0.0, 1.0);
    return Align(
      alignment: Alignment.center,
      child: Container(
        width: double.infinity,
        height: h,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(1.5),
        ),
      ),
    );
  }
}
