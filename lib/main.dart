
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:drone_control_ios/widgets/drone_joystick.dart';

const bg = Color(0xFF0B0C12);
const panel = Color(0xFF14141E);
const violet = Color(0xFFB9A0FF);
const mint = Color(0xFF72E0CF);
const muted = Color(0xFF9293A8);
const borderColor = Color(0xFF30283F);

void main() => runApp(const NovaFlightApp());

class NovaFlightApp extends StatelessWidget {
  const NovaFlightApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NOVA FLIGHT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        useMaterial3: true,
      ),
      home: const FlightScreen(),
    );
  }
}

enum LinkState { unknown, checking, unavailable }

class FlightScreen extends StatefulWidget {
  const FlightScreen({super.key});

  @override
  State<FlightScreen> createState() => _FlightScreenState();
}

class _FlightScreenState extends State<FlightScreen> {
  bool armed = false;
  bool flying = false;

  double altitude = 0;
  double battery = 84;
  double throttle = 0;
  double yaw = 0;
  double pitch = 0;
  double roll = 0;

  String flightMode = 'ANGLE';
  LinkState linkState = LinkState.unknown;

  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF292437),
      ),
    );
  }

  void toggleArm() {
    if (armed && flying) {
      showMessage('Aterizează în simulare înainte de dezarmare.');
      return;
    }

    setState(() => armed = !armed);
  }

  void takeOff() {
    if (!armed) {
      showMessage('Armează drona simulată mai întâi.');
      return;
    }

    setState(() {
      flying = true;
      altitude = 1.5;
      throttle = math.max(throttle, 50);
    });
  }

  void land() {
    setState(() {
      flying = false;
      altitude = 0;
      throttle = 0;
      yaw = 0;
      pitch = 0;
      roll = 0;
    });
  }

  void testWifi() {
    setState(() => linkState = LinkState.checking);

    // Verificarea reală va fi implementată când adăugăm
    // comunicația Wi-Fi cu ESP32-S3.
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() => linkState = LinkState.unavailable);
      showMessage(
        'Testul real nu este implementat încă. '
        'Nicio conexiune nu a fost verificată.',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 700;

            return ListView(
              padding: EdgeInsets.symmetric(
                horizontal: wide ? 28 : 16,
                vertical: 14,
              ),
              children: [
                _header(),
                const SizedBox(height: 20),
                _telemetry(),
                const SizedBox(height: 14),
                _wifiPanel(),
                const SizedBox(height: 22),
                _sectionTitle('FLIGHT COMMANDS', '01'),
                const SizedBox(height: 12),
                _commands(),
                const SizedBox(height: 22),
                _sectionTitle('DUAL STICK CONTROL', '02'),
                const SizedBox(height: 12),
                _joysticks(wide),
                const SizedBox(height: 14),
                _inputPanel(),
                const SizedBox(height: 14),
                _modePanel(),
                const SizedBox(height: 18),
                const Text(
                  'SIMULATION MODE  •  NO REAL FLIGHT COMMANDS',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: muted,
                    fontSize: 10,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFF211A32),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0xFF51416C)),
          ),
          child: const Icon(Icons.blur_on, color: violet, size: 30),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AEROSPACE SYSTEMS',
                style: TextStyle(
                  color: muted,
                  fontSize: 9,
                  letterSpacing: 2,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'NOVA FLIGHT',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF211A32),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            children: [
              Icon(Icons.circle, color: violet, size: 7),
              SizedBox(width: 6),
              Text(
                'SIM',
                style: TextStyle(
                  color: violet,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _telemetry() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _decoration(),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _metric(
                  'ALTITUDE',
                  '${altitude.toStringAsFixed(1)} m',
                  Icons.height,
                  violet,
                ),
              ),
              Container(width: 1, height: 55, color: borderColor),
              Expanded(
                child: _metric(
                  'BATTERY',
                  '${battery.toInt()}%',
                  Icons.battery_5_bar,
                  mint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: battery / 100,
              minHeight: 5,
              backgroundColor: Colors.white10,
              color: mint,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.sensors, color: muted, size: 17),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'FLIGHT TELEMETRY',
                  style: TextStyle(
                    color: muted,
                    fontSize: 10,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              Text(
                armed ? 'ARMED' : 'DISARMED',
                style: TextStyle(
                  color: armed ? const Color(0xFFF5BD65) : muted,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              color: muted,
              fontSize: 10,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _wifiPanel() {
    final checking = linkState == LinkState.checking;
    final unavailable = linkState == LinkState.unavailable;

    final statusColor = checking
        ? const Color(0xFFF5BD65)
        : unavailable
            ? const Color(0xFFFF9A83)
            : muted;

    final statusText = checking
        ? 'CHECKING'
        : unavailable
            ? 'NOT VERIFIED'
            : 'NOT TESTED';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _decoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF211A32),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.wifi, color: violet),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ESP32 CONNECTION',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Wi-Fi link diagnostics',
                      style: TextStyle(color: muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Real Wi-Fi testing is not configured yet.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: checking ? null : testWifi,
              icon: checking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_find, size: 18),
              label: Text(
                checking ? 'CHECKING...' : 'TEST CONNECTION',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: violet,
                side: const BorderSide(color: Color(0xFF51416C)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, String number) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 17,
          decoration: BoxDecoration(
            color: violet,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              letterSpacing: 1.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Text(number, style: const TextStyle(color: muted, fontSize: 11)),
      ],
    );
  }

  Widget _commands() {
    return Row(
      children: [
        Expanded(
          child: _command(
            armed ? 'DISARM' : 'ARM',
            armed ? Icons.lock : Icons.power_settings_new,
            armed ? const Color(0xFF6B3039) : const Color(0xFF302344),
            violet,
            toggleArm,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _command(
            'TAKEOFF',
            Icons.flight_takeoff,
            const Color(0xFF183B3B),
            mint,
            takeOff,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _command(
            'LAND',
            Icons.flight_land,
            const Color(0xFF40221F),
            const Color(0xFFFF9A83),
            land,
          ),
        ),
      ],
    );
  }

  Widget _command(
    String label,
    IconData icon,
    Color background,
    Color foreground,
    VoidCallback action,
  ) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: action,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 78,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: foreground.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foreground, size: 22),
              const SizedBox(height: 8),
              FittedBox(
                child: Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  
Widget _joysticks(bool wide) {
  return Container(
    padding: EdgeInsets.all(wide ? 18 : 8),
    decoration: _decoration(),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DroneJoystick(
            title: 'LEFT STICK',
            subtitle: 'THROTTLE / YAW',
            accent: violet,
            isThrottle: true,
            size: 220,
            onChanged: (values) {
              setState(() {
                yaw = values.x * 100;
                throttle = values.y;
              });
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: DroneJoystick(
            title: 'RIGHT STICK',
            subtitle: 'PITCH / ROLL',
            accent: mint,
            isThrottle: false,
            size: 220,
            onChanged: (values) {
              setState(() {
                roll = values.x * 100;
                pitch = values.y * 100;
              });
            },
          ),
        ),
      ],
    ),
  );
}


  Widget _inputPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _decoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CONTROL INPUTS',
            style: TextStyle(
              color: muted,
              fontSize: 10,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          _input('THROTTLE', throttle, violet, centered: false),
          _input('YAW', yaw, violet, centered: true),
          _input('PITCH', pitch, mint, centered: true),
          _input('ROLL', roll, mint, centered: true),
        ],
      ),
    );
  }

  Widget _input(
    String label,
    double value,
    Color color, {
    required bool centered,
  }) {
    final text = '${value >= 0 ? '+' : ''}${value.toStringAsFixed(0)}%';

    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
              ),
              Text(
                text,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: 5,
              width: double.infinity,
              child: CustomPaint(
                painter: InputBarPainter(
                  value: value / 100,
                  color: color,
                  centered: centered,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modePanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: _decoration(),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: flightMode,
          isExpanded: true,
          dropdownColor: panel,
          iconEnabledColor: violet,
          items: const [
            DropdownMenuItem(value: 'ANGLE', child: Text('ANGLE MODE')),
            DropdownMenuItem(value: 'ALT HOLD', child: Text('ALTITUDE HOLD')),
            DropdownMenuItem(value: 'POS HOLD', child: Text('POSITION HOLD')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => flightMode = value);
          },
        ),
      ),
    );
  }

  BoxDecoration _decoration() {
    return BoxDecoration(
      color: panel,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: borderColor),
    );
  }
}

class Joystick extends StatefulWidget {
  final String title;
  final String subtitle;
  final Color color;
  final ValueChanged2 onChanged;
  final double? initialThrottle;

  const Joystick({
    super.key,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onChanged,
    this.initialThrottle,
  });

  @override
  State<Joystick> createState() => _JoystickState();
}

typedef ValueChanged2 = void Function(double x, double y);

class _JoystickState extends State<Joystick> {
  Offset position = Offset.zero;
  bool dragging = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialThrottle != null) {
      position = Offset(0, widget.initialThrottle! / 50 - 1);
    }
  }

  Offset normalize(Offset point, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * 0.43;
    final delta = point - center;
    final distance = delta.distance;
    final limited = distance > radius ? delta * radius / distance : delta;

    return Offset(
      (limited.dx / radius).clamp(-1.0, 1.0).toDouble(),
      (-limited.dy / radius).clamp(-1.0, 1.0).toDouble(),
    );
  }

  void emit() {
    widget.onChanged(
      position.dx,
      widget.initialThrottle != null
          ? (position.dy + 1) * 50
          : position.dy,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          widget.title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          widget.subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted, fontSize: 9),
        ),
        const SizedBox(height: 14),
        AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(
                constraints.maxWidth,
                constraints.maxHeight,
              );

              return GestureDetector(
                onPanStart: (details) {
                  setState(() {
                    dragging = true;
                    position = normalize(details.localPosition, size);
                  });
                  emit();
                },
                onPanUpdate: (details) {
                  setState(() {
                    position = normalize(details.localPosition, size);
                  });
                  emit();
                },
                onPanEnd: (_) {
                  setState(() {
                    dragging = false;
                    if (widget.initialThrottle == null) {
                      position = Offset.zero;
                    } else {
                      position = Offset(0, position.dy);
                    }
                  });
                  emit();
                },
                onPanCancel: () {
                  setState(() {
                    dragging = false;
                    if (widget.initialThrottle == null) {
                      position = Offset.zero;
                    } else {
                      position = Offset(0, position.dy);
                    }
                  });
                  emit();
                },
                child: CustomPaint(
                  painter: JoystickPainter(
                    position: position,
                    color: widget.color,
                    dragging: dragging,
                  ),
                  child: const SizedBox.expand(),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Text(
          widget.initialThrottle != null
              ? 'THR ${((position.dy + 1) * 50).round()}%'
              : 'X ${(position.dx * 100).round()}  '
                  'Y ${(position.dy * 100).round()}',
          style: TextStyle(
            color: widget.color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class JoystickPainter extends CustomPainter {
  final Offset position;
  final Color color;
  final bool dragging;

  JoystickPainter({
    required this.position,
    required this.color,
    required this.dragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * 0.46;

    canvas.drawCircle(
      center,
      radius,
      Paint()..color = const Color(0xFF1D1A29),
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final grid = Paint()
      ..color = Colors.white10
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(center.dx - radius * 0.72, center.dy),
      Offset(center.dx + radius * 0.72, center.dy),
      grid,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius * 0.72),
      Offset(center.dx, center.dy + radius * 0.72),
      grid,
    );

    final knob = center +
        Offset(position.dx * radius, -position.dy * radius);

    canvas.drawLine(
      center,
      knob,
      Paint()
        ..color = color.withValues(alpha: 0.7)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawCircle(
      knob,
      radius * 0.34,
      Paint()..color = color.withValues(alpha: 0.13),
    );
    canvas.drawCircle(
      knob,
      radius * 0.25,
      Paint()..color = color,
    );
    canvas.drawCircle(
      knob,
      radius * 0.25,
      Paint()
        ..color = Colors.white38
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant JoystickPainter oldDelegate) {
    return oldDelegate.position != position ||
        oldDelegate.color != color ||
        oldDelegate.dragging != dragging;
  }
}

class InputBarPainter extends CustomPainter {
  final double value;
  final Color color;
  final bool centered;

  InputBarPainter({
    required this.value,
    required this.color,
    required this.centered,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.white10,
    );

    final amount = value.abs().clamp(0.0, 1.0);

    if (centered) {
      final middle = size.width / 2;
      canvas.drawRect(
        Rect.fromLTWH(
          value >= 0 ? middle : middle - amount * middle,
          0,
          amount * middle,
          size.height,
        ),
        Paint()..color = color,
      );
    } else {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, amount * size.width, size.height),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant InputBarPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.color != color ||
        oldDelegate.centered != centered;
  }
}
