import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A sleek, simple horizontal slider-based color picker matching the design
/// with a full-spectrum Hue slider, a Shade/Alpha slider, and a floating tooltip.
class SimpleColorSliderPicker extends StatefulWidget {
  final Color pickerColor;
  final ValueChanged<Color> onColorChanged;

  const SimpleColorSliderPicker({
    super.key,
    required this.pickerColor,
    required this.onColorChanged,
  });

  @override
  State<SimpleColorSliderPicker> createState() =>
      _SimpleColorSliderPickerState();
}

class _SimpleColorSliderPickerState extends State<SimpleColorSliderPicker> {
  late double _hue; // 0.0 - 360.0
  late double _shade; // 0.0 - 1.0 (controlling value / lightness)
  bool _isDraggingHue = false;
  bool _isDraggingShade = false;

  static const double _thumbDiameter = 24.0;
  static const double _trackHeight = 12.0;
  static const double _sliderHeight = 32.0;

  @override
  void initState() {
    super.initState();
    _initFromColor(widget.pickerColor);
  }

  @override
  void didUpdateWidget(covariant SimpleColorSliderPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pickerColor != widget.pickerColor) {
      _initFromColor(widget.pickerColor);
    }
  }

  void _initFromColor(Color color) {
    final hsv = HSVColor.fromColor(color);
    _hue = hsv.hue;
    if (hsv.value < 0.99) {
      _shade = (hsv.value * 0.5).clamp(0.0, 0.5);
    } else {
      _shade = (0.5 + (1.0 - hsv.saturation) * 0.5).clamp(0.5, 1.0);
    }
  }

  Color _computeColor() {
    if (_shade <= 0.5) {
      final v = (_shade / 0.5).clamp(0.05, 1.0);
      return HSVColor.fromAHSV(1.0, _hue, 1.0, v).toColor();
    } else {
      final s = (1.0 - ((_shade - 0.5) / 0.5)).clamp(0.0, 1.0);
      return HSVColor.fromAHSV(1.0, _hue, s, 1.0).toColor();
    }
  }

  void _updateFromHue(double progress) {
    setState(() {
      _hue = (progress * 360.0).clamp(0.0, 360.0);
    });
    widget.onColorChanged(_computeColor());
  }

  void _updateFromShade(double progress) {
    setState(() {
      _shade = progress.clamp(0.0, 1.0);
    });
    widget.onColorChanged(_computeColor());
  }

  @override
  Widget build(BuildContext context) {
    final currentColor = _computeColor();
    final hueColor = HSVColor.fromAHSV(1.0, _hue, 1.0, 1.0).toColor();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Slider: Hue Spectrum (with floating tooltip)
          _buildSliderWithTooltip(
            progress: _hue / 360.0,
            tooltipValue: '${((_hue / 360.0) * 100).round()}%',
            isDragging: _isDraggingHue,
            trackWidget: Container(
              height: _trackHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(50),
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFFFF0000), // Red
                    Color(0xFFFF8800), // Orange
                    Color(0xFFFFFF00), // Yellow
                    Color(0xFF00FF00), // Green
                    Color(0xFF00FFFF), // Cyan
                    Color(0xFF0066FF), // Blue
                    Color(0xFF8800FF), // Violet
                    Color(0xFFFF00FF), // Magenta
                    Color(0xFFFF0000), // Red
                  ],
                ),
              ),
            ),
            thumbColor: hueColor,
            onDragStart: () => setState(() => _isDraggingHue = true),
            onDragEnd: () => setState(() => _isDraggingHue = false),
            onProgressChanged: _updateFromHue,
          ),

          const SizedBox(height: 16),

          // Bottom Slider: Shade / Checkerboard Slider
          _buildSliderWithTooltip(
            progress: _shade,
            tooltipValue: '${(_shade * 100).round()}%',
            isDragging: _isDraggingShade,
            trackWidget: ClipRRect(
              borderRadius: BorderRadius.circular(50),
              child: Container(
                height: _trackHeight,
                foregroundDecoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black,
                      hueColor,
                      Colors.white,
                    ],
                  ),
                ),
                child: CustomPaint(
                  painter: _CheckerTrackPainter(),
                ),
              ),
            ),
            thumbColor: currentColor,
            onDragStart: () => setState(() => _isDraggingShade = true),
            onDragEnd: () => setState(() => _isDraggingShade = false),
            onProgressChanged: _updateFromShade,
          ),
        ],
      ),
    );
  }

  Widget _buildSliderWithTooltip({
    required double progress,
    required String tooltipValue,
    required bool isDragging,
    required Widget trackWidget,
    required Color thumbColor,
    required VoidCallback onDragStart,
    required VoidCallback onDragEnd,
    required ValueChanged<double> onProgressChanged,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        final thumbOffset =
            progress.clamp(0.0, 1.0) * (trackWidth - _thumbDiameter);

        final trackTop = (_sliderHeight - _trackHeight) / 2;
        final thumbTop = (_sliderHeight - _thumbDiameter) / 2;

        return SizedBox(
          height: _sliderHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Center track (vertically centered)
              Positioned(
                left: 0,
                right: 0,
                top: trackTop,
                child: trackWidget,
              ),

              // Thumb (vertically centered on track)
              Positioned(
                left: thumbOffset,
                top: thumbTop,
                child: Container(
                  width: _thumbDiameter,
                  height: _thumbDiameter,
                  decoration: BoxDecoration(
                    color: thumbColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white,
                      width: 3.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),

              // Tooltip custom bubble paint with lime text, points directly to thumb
              Positioned(
                left: (thumbOffset + _thumbDiameter / 2 - 22)
                    .clamp(0.0, math.max(0.0, trackWidth - 44.0)),
                top: thumbTop - 28,
                child: AnimatedOpacity(
                  opacity: isDragging ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 150),
                  child: CustomPaint(
                    painter: _TooltipBubblePainter(
                      color: const Color(0xFF18181B),
                    ),
                    child: SizedBox(
                      width: 44,
                      height: 28,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            tooltipValue,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF84CC16), // Bright lime from reference
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Gesture Detector overlay covering entire slider row
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanDown: (details) {
                    onDragStart();
                    final localX = details.localPosition.dx;
                    final newProgress = (localX - _thumbDiameter / 2) /
                        (trackWidth - _thumbDiameter);
                    onProgressChanged(newProgress.clamp(0.0, 1.0));
                  },
                  onPanUpdate: (details) {
                    final localX = details.localPosition.dx;
                    final newProgress = (localX - _thumbDiameter / 2) /
                        (trackWidth - _thumbDiameter);
                    onProgressChanged(newProgress.clamp(0.0, 1.0));
                  },
                  onPanEnd: (_) => onDragEnd(),
                  onPanCancel: () => onDragEnd(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Paints the black tooltip bubble with downward pointer arrow matching the reference
class _TooltipBubblePainter extends CustomPainter {
  final Color color;

  _TooltipBubblePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const r = 7.0;
    const arrowW = 8.0;
    const arrowH = 5.0;
    final bodyH = size.height - arrowH;
    final w = size.width;

    final path = Path()
      ..moveTo(r, 0)
      ..lineTo(w - r, 0)
      ..quadraticBezierTo(w, 0, w, r)
      ..lineTo(w, bodyH - r)
      ..quadraticBezierTo(w, bodyH, w - r, bodyH)
      ..lineTo(w / 2 + arrowW / 2, bodyH)
      ..lineTo(w / 2, size.height) // pointer tip
      ..lineTo(w / 2 - arrowW / 2, bodyH)
      ..lineTo(r, bodyH)
      ..quadraticBezierTo(0, bodyH, 0, bodyH - r)
      ..lineTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..close();

    canvas.drawShadow(
      path,
      Colors.black.withValues(alpha: 0.25),
      3,
      false,
    );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Paints the checkered pattern on the shade/transparency track
class _CheckerTrackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint1 = Paint()..color = const Color(0xFFE2E8F0);
    final paint2 = Paint()..color = const Color(0xFFF8FAFC);
    const boxSize = 4.0;

    for (double x = 0; x < size.width; x += boxSize) {
      for (double y = 0; y < size.height; y += boxSize) {
        final isEven =
            ((x / boxSize).floor() + (y / boxSize).floor()) % 2 == 0;
        canvas.drawRect(
          Rect.fromLTWH(
            x,
            y,
            math.min(boxSize, size.width - x),
            math.min(boxSize, size.height - y),
          ),
          isEven ? paint1 : paint2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
