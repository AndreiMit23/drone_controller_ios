import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Reusable touch joystick for NOVA FLIGHT.
///
/// Left stick: set [isThrottle] to true. X reports yaw in -1..1; Y reports
/// throttle in 0..100 and stays where released. Yaw springs back to zero.
/// Right stick: X reports roll and Y reports pitch, both in -1..1; both
/// axes spring back to zero on release.
class DroneJoystick extends StatefulWidget {
  const DroneJoystick({
    super.key,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.isThrottle,
    required this.onChanged,
    this.size = 220,
  });

  final String title;
  final String subtitle;
  final Color accent;
  final bool isThrottle;
  final ValueChanged<JoystickValues> onChanged;
  final double size;

  @override
  State<DroneJoystick> createState() => _DroneJoystickState();
}

class JoystickValues {
  const JoystickValues({required this.x, required this.y});

  /// Horizontal axis, normalized to -1..1.
  final double x;

  /// Throttle joystick: 0..100. Other joystick: vertical axis -1..1.
  final double y;
}

class _DroneJoystickState extends State<DroneJoystick>
    with SingleTickerProviderStateMixin {
  Offset _position = const Offset(0, -1); // throttle starts at 0%, knob at bottom
  Offset _animationStart = Offset.zero;
  Offset _animationEnd = Offset.zero;
  late final AnimationController _returnController;
  bool _dragging = false;
  int? _pointer;
  final List<Offset> _trail = <Offset>[];

  @override
  void initState() {
    super.initState();
    if (!widget.isThrottle) _position = Offset.zero;
    _returnController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addListener(_animateReturn);
  }

  @override
  void didUpdateWidget(covariant DroneJoystick oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isThrottle != widget.isThrottle) {
      _position = widget.isThrottle
          ? const Offset(0, -1)
          : Offset.zero;
    }
  }

  @override
  void dispose() {
    _returnController.dispose();
    super.dispose();
  }

  double _clamp(double value) => value.clamp(-1.0, 1.0).toDouble();

  void _emit() {
    widget.onChanged(JoystickValues(
      x: _position.dx,
      y: widget.isThrottle ? ((_position.dy + 1) * 50).clamp(0, 100).toDouble() : _position.dy,
    ));
  }

  Offset _normalise(Offset localPosition, Size size) {
    final travel = size.width * .34;
    final center = Offset(size.width / 2, size.height / 2);
    return Offset(
      _clamp((localPosition.dx - center.dx) / travel),
      _clamp(-(localPosition.dy - center.dy) / travel),
    );
  }

  void _start(PointerEvent event, BoxConstraints constraints) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _returnController.stop();
    _dragging = true;
    final size = Size(constraints.maxWidth, constraints.maxHeight);
    final point = _normalise(event.localPosition, size);

    // If the user touches the knob, preserve the offset so it doesn't jump.
    final knobHit = (Offset(point.dx - _position.dx, point.dy - _position.dy)).distance < .26;
    final offset = knobHit ? _position - point : Offset.zero;
    _position = Offset(_clamp(point.dx + offset.dx), _clamp(point.dy + offset.dy));
    _addTrail();
    _emit();
    setState(() {});
  }

  void _move(PointerEvent event, BoxConstraints constraints) {
    if (_pointer != event.pointer) return;
    final size = Size(constraints.maxWidth, constraints.maxHeight);
    _position = _normalise(event.localPosition, size);
    _addTrail();
    _emit();
    setState(() {});
  }

  void _end(PointerEvent event) {
    if (_pointer != event.pointer) return;
    _pointer = null;
    _dragging = false;
    _animationStart = _position;
    _animationEnd = widget.isThrottle ? Offset(0, _position.dy) : Offset.zero;
    _returnController.forward(from: 0);
    setState(() {});
  }

  void _animateReturn() {
    final t = Curves.easeOutCubic.transform(_returnController.value);
    _position = Offset.lerp(_animationStart, _animationEnd, t)!;
    _emit();
    if (mounted) setState(() {});
  }

  void _addTrail() {
    _trail.add(_position);
    if (_trail.length > 18) _trail.removeAt(0);
  }

  String _signed(double value) {
    final number = (value * 100).round();
    return number > 0 ? '+$number' : '$number';
  }

  @override
  Widget build(BuildContext context) {
    final throttle = ((_position.dy + 1) * 50).clamp(0, 100).round();
    final firstValue = widget.isThrottle ? '$throttle%' : _signed(_position.dy);
    final firstLabel = widget.isThrottle ? 'THR' : 'PIT';
    final secondValue = _signed(_position.dx);
    final secondLabel = widget.isThrottle ? 'YAW' : 'ROL';

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 15, 12, 13),
      decoration: BoxDecoration(
        color: const Color(0xFF141720),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: widget.accent.withValues(alpha: .22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.title.toUpperCase(), style: const TextStyle(
            color: Color(0xFFE8EAF2), fontSize: 14, fontWeight: FontWeight.w700,
            letterSpacing: 1.8,
          )),
          const SizedBox(height: 5),
          Text(widget.subtitle.toUpperCase(), style: const TextStyle(
            color: Color(0xFF8B91A5), fontSize: 10, letterSpacing: 1.6,
          )),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, constraints) {
            final gateSize = math.min(widget.size, constraints.maxWidth);
            return SizedBox(
              width: gateSize,
              height: gateSize,
              child: Listener(
                onPointerDown: (event) => _start(event, BoxConstraints.tight(Size(gateSize, gateSize))),
                onPointerMove: (event) => _move(event, BoxConstraints.tight(Size(gateSize, gateSize))),
                onPointerUp: _end,
                onPointerCancel: _end,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (details) {
                    // Listener handles pointer coordinates and capture; this keeps touch gestures active.
                  },
                  child: CustomPaint(
                    painter: _GimbalPainter(
                      position: _position,
                      trail: List<Offset>.unmodifiable(_trail),
                      accent: widget.accent,
                      isThrottle: widget.isThrottle,
                      active: _dragging,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(child: _Readout(label: firstLabel, value: firstValue, accent: widget.accent)),
              Expanded(child: _Readout(label: secondLabel, value: secondValue, accent: widget.accent)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({required this.label, required this.value, required this.accent});
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(label, style: const TextStyle(color: Color(0xFF8B91A5), fontSize: 10, letterSpacing: 1.6)),
      const SizedBox(height: 5),
      Text(value, style: TextStyle(color: accent, fontSize: 18, fontFamily: 'monospace', fontWeight: FontWeight.w600)),
    ],
  );
}

class _GimbalPainter extends CustomPainter {
  const _GimbalPainter({
    required this.position,
    required this.trail,
    required this.accent,
    required this.isThrottle,
    required this.active,
  });

  final Offset position;
  final List<Offset> trail;
  final Color accent;
  final bool isThrottle;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final travel = size.width * .34;
    final radius = size.width * .13;
    final rect = Offset.zero & size;

    final bg = Paint()..shader = const RadialGradient(
      center: Alignment(0, -.28), radius: 1.2,
      colors: [Color(0xFF1D2030), Color(0xFF10121A)],
    ).createShader(rect);
    final well = RRect.fromRectAndRadius(rect, Radius.circular(size.width * .14));
    canvas.drawRRect(well, bg);
    canvas.drawRRect(well, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = accent.withValues(alpha: active ? .85 : .35));

    final guidePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = accent.withValues(alpha: .16);
    for (final factor in [.25, .5, .75, 1.0]) {
      canvas.drawCircle(center, travel * factor, guidePaint);
    }
    canvas.drawLine(Offset(center.dx - travel, center.dy), Offset(center.dx + travel, center.dy), guidePaint);
    canvas.drawLine(Offset(center.dx, center.dy - travel), Offset(center.dx, center.dy + travel), guidePaint);

    if (isThrottle) {
      final gaugeRect = Rect.fromLTWH(size.width * .07, size.height * .13, 4, size.height * .74);
      canvas.drawRRect(RRect.fromRectAndRadius(gaugeRect, const Radius.circular(3)), Paint()..color = const Color(0xFF0B0D13));
      final fillHeight = gaugeRect.height * ((position.dy + 1) / 2);
      final fillRect = Rect.fromLTWH(gaugeRect.left, gaugeRect.bottom - fillHeight, gaugeRect.width, fillHeight);
      canvas.drawRRect(RRect.fromRectAndRadius(fillRect, const Radius.circular(3)), Paint()
        ..shader = LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter,
          colors: [accent.withValues(alpha: .5), accent]).createShader(gaugeRect));
    }

    if (trail.length > 1) {
      final trailPaint = Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
      for (var i = 1; i < trail.length; i++) {
        trailPaint
          ..color = accent.withValues(alpha: i / trail.length * .35)
          ..strokeWidth = size.width * .025 * i / trail.length;
        canvas.drawLine(
          Offset(center.dx + trail[i - 1].dx * travel, center.dy - trail[i - 1].dy * travel),
          Offset(center.dx + trail[i].dx * travel, center.dy - trail[i].dy * travel),
          trailPaint,
        );
      }
    }

    final knobCenter = Offset(center.dx + position.dx * travel, center.dy - position.dy * travel);
    canvas.drawCircle(knobCenter + Offset(0, 5), radius * 1.12, Paint()..color = Colors.black.withValues(alpha: .45)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    canvas.drawCircle(knobCenter, radius, Paint()..shader = RadialGradient(
      center: const Alignment(-.35, -.45),
      colors: [Color.lerp(Colors.white, accent, .45)!, accent, Color.lerp(accent, Colors.black, .45)!],
    ).createShader(Rect.fromCircle(center: knobCenter, radius: radius)));
    canvas.drawCircle(knobCenter, radius * .62, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = Colors.white.withValues(alpha: .28));
  }

  @override
  bool shouldRepaint(covariant _GimbalPainter oldDelegate) =>
      oldDelegate.position != position || oldDelegate.active != active ||
      oldDelegate.accent != accent || oldDelegate.trail != trail || oldDelegate.isThrottle != isThrottle;
}
