import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'package:drone_control_ios/widgets/drone_joystick.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const bg = Color(0xFF080B12);
const panel = Color(0xFF111724);
const violet = Color(0xFF8B70FF);
const mint = Color(0xFF35E5CC);
const muted = Color(0xFF8995AA);
const danger = Color(0xFFFF637D);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(const NovaFlightApp());
}

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
        colorScheme: ColorScheme.fromSeed(
          seedColor: violet,
          brightness: Brightness.dark,
        ),
      ),
      home: const FlightScreen(),
    );
  }
}

class FlightScreen extends StatefulWidget {
  const FlightScreen({super.key});

  @override
  State<FlightScreen> createState() => _FlightScreenState();
}

class _FlightScreenState extends State<FlightScreen> {
  double yaw = 0;
  double throttle = 0;
  double roll = 0;
  double pitch = 0;

  double? altitude;
  double? battery;

  bool armed = false;
  // True means the app is requesting ARM via AUX1; it is not proof the FC armed.
  bool armCommandRequested = false;
  bool navAltHoldRequested = false;
  bool connected = false;
  bool connecting = false;
  bool inFlight = false;
  bool flightControllerConnected = false;
  bool telemetrySimulated = false;

  String droneStatus = 'DISCONNECTED';
  String flightMode = 'UNKNOWN';
  String host = '192.168.4.1';
  String connectionError = '';

  Timer? pollingTimer;
  bool _pollInProgress = false;

  WebSocketChannel? _rcChannel;
  StreamSubscription? _rcSubscription;
  Timer? _rcTimer;

  bool _rcConnected = false;

  Uri get _baseUri => Uri.parse('http://$host');

  int _axisToRc(double value) {
    return (1500 + value * 5).round().clamp(1000, 2000);
  }

  int _throttleToRc(double value) {
    return (1000 + value * 10).round().clamp(1000, 2000);
  }

  void _sendRcFrame() {
    if (!_rcConnected || _rcChannel == null) return;

    final rcData = {
      'roll': _axisToRc(roll),
      'pitch': _axisToRc(pitch),
      'yaw': _axisToRc(yaw),
      'throttle': _throttleToRc(throttle),
      'aux1': armCommandRequested ? 2000 : 1000,
      'aux2': navAltHoldRequested ? 1800 : 1000,
    };

    debugPrint(
      '[FLUTTER RC TX] '
      'AUX1=${rcData['aux1']} '
      'AUX2=${rcData['aux2']} '
      'Throttle=${rcData['throttle']}',
    );

    try {
      _rcChannel!.sink.add(jsonEncode(rcData));
    } catch (error) {
      debugPrint('[WS] RC transmission error: $error');
    }
  }

  Future<void> _connectWebSocket() async {
    final channel = WebSocketChannel.connect(Uri.parse('ws://$host:81'));

    _rcChannel = channel;

    try {
      await channel.ready.timeout(const Duration(seconds: 5));
      debugPrint('[WS] CONNECTION SUCCESS');
    } catch (e) {
      debugPrint('[WS] CONNECTION FAILED: $e');
      rethrow;
    }

    await channel.ready.timeout(const Duration(seconds: 3));

    if (!mounted || _rcChannel != channel) {
      await channel.sink.close();
      throw Exception('WebSocket connection cancelled');
    }

    _rcConnected = true;

    _rcSubscription = channel.stream.listen(
      (message) {
        debugPrint('[WS] Received: $message');
      },
      onError: (error) {
        debugPrint('[WS] Error: $error');
        _handleWebSocketLost(channel);
      },
      onDone: () {
        debugPrint('[WS] Connection closed');
        _handleWebSocketLost(channel);
      },
    );

    _rcTimer?.cancel();

    _rcTimer = Timer.periodic(
      const Duration(milliseconds: 20),
      (_) => _sendRcFrame(),
    );

    debugPrint('[WS] RC transmission started at 50 Hz');
  }

  void _handleWebSocketLost(WebSocketChannel channel) {
    if (_rcChannel != channel) return;

    _rcTimer?.cancel();
    _rcTimer = null;
    _rcConnected = false;
    _rcChannel = null;

    if (!mounted) return;

    setState(() {
      connected = false;
      connecting = false;
      droneStatus = 'CONNECTION LOST';
      connectionError = 'WebSocket connection lost';
      flightControllerConnected = false;
      armed = false;
      armCommandRequested = false;
      navAltHoldRequested = false;
      inFlight = false;
      altitude = null;
      battery = null;
      flightMode = 'UNKNOWN';
    });

    pollingTimer?.cancel();
    pollingTimer = null;
    _rcSubscription = null; // starea aplicatiei actualizata
  }

  Future<void> _closeWebSocket() async {
    _rcTimer?.cancel();
    _rcTimer = null;

    final channel = _rcChannel;
    _rcChannel = null;
    _rcConnected = false;

    await _rcSubscription?.cancel();
    _rcSubscription = null;

    if (channel != null) {
      await channel.sink.close();
    }
  }

  @override
  void dispose() {
    pollingTimer?.cancel();
    _rcTimer?.cancel();
    unawaited(_closeWebSocket());

    super.dispose();
  }

  Future<Map<String, dynamic>> _getJson(String path) async {
    final response = await http
        .get(_baseUri.replace(path: path))
        .timeout(const Duration(seconds: 3));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('$path returned HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid JSON response');
    }
    return decoded;
  }

  dynamic _firstValue(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      if (data.containsKey(key) && data[key] != null) return data[key];
    }
    return null;
  }

  double? _numberFrom(Map<String, dynamic> data, List<String> keys) {
    final value = _firstValue(data, keys);
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  bool? _boolFrom(Map<String, dynamic> data, List<String> keys) {
    final value = _firstValue(data, keys);
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      if ([
        'true',
        '1',
        'yes',
        'connected',
        'online',
      ].contains(value.toLowerCase())) {
        return true;
      }
      if ([
        'false',
        '0',
        'no',
        'disconnected',
        'offline',
      ].contains(value.toLowerCase())) {
        return false;
      }
    }
    return null;
  }

  Future<void> _connect() async {
    if (connecting || connected) return;

    setState(() {
      connecting = true;
      connectionError = '';
      droneStatus = 'CONNECTING';
    });

    try {
      final health = await _getJson('/health');
      final healthStatus = (health['esp32'] ?? health['status'] ?? '')
          .toString()
          .toLowerCase();

      final isOnline =
          healthStatus == 'online' ||
          healthStatus == 'ok' ||
          healthStatus == 'true' ||
          health['online'] == true;

      if (!isOnline) {
        throw Exception('ESP32 health check did not report online');
      }

      await _refreshTelemetry();

      // Deschidem conexiunea WebSocket pentru comenzile RC.
      await _connectWebSocket();

      if (!mounted) return;
      setState(() {
        connected = true;
        connecting = false;
        droneStatus = 'ESP32 ONLINE';
        connectionError = '';
      });

      _startPolling();
    } catch (error) {
      await _closeWebSocket();
      if (!mounted) return;
      setState(() {
        connected = false;
        connecting = false;
        droneStatus = 'CONNECTION FAILED';
        connectionError = error.toString();
        flightControllerConnected = false;
        altitude = null;
        battery = null;
        armed = false;
        inFlight = false;
      });
      pollingTimer?.cancel();
      pollingTimer = null;

      unawaited(
        _closeWebSocket(),
      ); // daca esp32 nu raspunde atunci aplicatia nu transmite comenzi RC
    }
  }

  Future<void> _refreshTelemetry() async {
    final results = await Future.wait([
      _getJson('/status'),
      _getJson('/telemetry'),
    ]);

    final status = results[0];
    final telemetry = results[1];

    final fcValue = _firstValue(status, [
      'flightControllerConnected',
      'flight_controller_connected',
      'flightController',
      'flight_controller',
    ]);
    bool fcConnected = false;
    if (fcValue is bool) {
      fcConnected = fcValue;
    } else if (fcValue != null) {
      final normalized = fcValue.toString().toLowerCase();
      fcConnected =
          normalized == 'connected' ||
          normalized == 'online' ||
          normalized == 'true';
    }

    final armedValue =
        _boolFrom(status, ['armed', 'isArmed']) ??
        _boolFrom(telemetry, ['armed', 'isArmed']);
    final modeValue = _firstValue(status, [
      'mode',
      'flightMode',
      'flight_mode',
    ]);
    final modeValid = _boolFrom(status, ['mode_valid', 'modeValid']);

    final altitudeValue =
        _numberFrom(telemetry, [
          'altitudeMeters',
          'altitude_meters',
          'altitude',
          'altitude_m',
        ]) ??
        _numberFrom(status, [
          'altitudeMeters',
          'altitude_meters',
          'altitude',
          'altitude_m',
        ]);
    final batteryValue =
        _numberFrom(telemetry, [
          'batteryPercent',
          'battery_percent',
          'battery_percent_remaining',
        ]) ??
        _numberFrom(status, [
          'batteryPercent',
          'battery_percent',
          'battery_percent_remaining',
        ]);

    final altitudeValid = _boolFrom(telemetry, [
      'altitudeValid',
      'altitude_valid',
    ]);
    final batteryValid = _boolFrom(telemetry, [
      'batteryValid',
      'battery_valid',
    ]);
    final simulated =
        _boolFrom(status, ['simulated', 'telemetrySimulated']) ??
        _boolFrom(telemetry, ['simulated', 'telemetrySimulated']) ??
        false;

    if (!mounted) return;
    setState(() {
      flightControllerConnected = fcConnected;
      if (armedValue != null) {
        armed = armedValue;
        inFlight = false;
      } else {
        armed = false;
        inFlight = false;
      }

      if (modeValue != null &&
          (modeValid == null || modeValid) &&
          modeValue.toString().isNotEmpty) {
        flightMode = modeValue.toString();
      } else {
        flightMode = 'UNKNOWN';
      }

      altitude = altitudeValue != null && altitudeValid != false
          ? altitudeValue
          : null;
      battery = batteryValue != null && batteryValid != false
          ? batteryValue
          : null;
      telemetrySimulated = simulated;
    });
  }

  void _startPolling() {
    pollingTimer?.cancel();
    pollingTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!connected || _pollInProgress) return;
      _pollInProgress = true;
      try {
        await _refreshTelemetry();
      } catch (error) {
        if (mounted) {
          setState(() {
            connected = false;
            connecting = false;
            droneStatus = 'CONNECTION LOST';
            connectionError = error.toString();
            flightControllerConnected = false;
            armCommandRequested = false;
            navAltHoldRequested = false;
            altitude = null;
            battery = null;
            armed = false;
            inFlight = false;
            flightMode = 'UNKNOWN';
          });
        }
        pollingTimer?.cancel();
        pollingTimer = null;
        unawaited(_closeWebSocket());
      } finally {
        _pollInProgress = false;
      }
    });
  }

  void _disconnect() {
    
    _rcTimer?.cancel();
    // Trimitem o comandă neutră înainte de închiderea conexiunii.
    if (_rcConnected && _rcChannel != null) {
      _rcChannel!.sink.add(
        jsonEncode({
          'roll': 1500,
          'pitch': 1500,
          'yaw': 1500,
          'throttle': 1000,
          'aux1': 1000,
          'aux2': 1000,
        }),
      );
    }

    pollingTimer?.cancel();
    pollingTimer = null;

    unawaited(_closeWebSocket());

    if (!mounted) return;

    setState(() {
      connected = false;
      connecting = false;
      armed = false;
      armCommandRequested = false;
      navAltHoldRequested = false;
      inFlight = false;
      flightControllerConnected = false;
      altitude = null;
      battery = null;
      flightMode = 'UNKNOWN';
      droneStatus = 'DISCONNECTED';
      connectionError = '';

      // Revenim la poziția neutră.
      yaw = 0;
      roll = 0;
      pitch = 0;
      throttle = 0;
    });
  }

  Future<void> _toggleArm() async {
    if (!connected || !_rcConnected || _rcChannel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connect to the drone before sending ARM.'),
        ),
      );
      return;
    }

    // DISARM is always available immediately while the WebSocket is connected.
    if (armed || armCommandRequested) {
      setState(() => armCommandRequested = false);
      _sendRcFrame();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('DISARM command sent (AUX1 = 1000).')),
      );
      return;
    }

    // Do not request ARM unless throttle is at its minimum.
    if (_throttleToRc(throttle) > 1000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Move throttle fully down before ARM.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: panel,
        title: const Text('Confirm ARM command'),
        content: const Text(
          'This sends AUX1 = 2000 and can arm the flight controller. '
          'Motors may start. Keep all propellers removed and the throttle at minimum. '
          'Do not use this to fly until RC-loss failsafe has been verified.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('SEND ARM'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted || !_rcConnected || _rcChannel == null) {
      return;
    }

    setState(() => armCommandRequested = true);
    debugPrint('[ARM DEBUG] Confirmation accepted!');
    debugPrint('[ARM DEBUG] armCommandRequested = $armCommandRequested');
    debugPrint('[ARM DEBUG] connected = $connected');
    debugPrint('[ARM DEBUG] rcConnected = $_rcConnected');
    _sendRcFrame();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'ARM request sent (AUX1 = 2000). Check INAV Modes/Receiver.',
        ),
      ),
    );
  }

  void _toggleNavAltHold() {
    if (!connected || !_rcConnected || _rcChannel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connect to the drone first.')),
      );
      return;
    }

    setState(() {
      navAltHoldRequested = !navAltHoldRequested;
    });

    _sendRcFrame();

    debugPrint('[NAV ALTHOLD] AUX2=${navAltHoldRequested ? 1800 : 1000}');
  }

  Future<void> _toggleFlight() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'TAKEOFF/LAND are disabled until flight-controller commands are implemented and verified.',
        ),
      ),
    );
  }

  Future<void> _showConnectionDialog() async {
    final controller = TextEditingController(text: host);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: panel,
          title: const Text('Wi-Fi connection'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ESP32 HTTP address',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    hintText: '192.168.4.1',
                    prefixIcon: Icon(Icons.router),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      connected ? Icons.check_circle : Icons.circle_outlined,
                      color: connected ? mint : muted,
                      size: 17,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        droneStatus,
                        style: TextStyle(
                          color: connected ? mint : muted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                if (connectionError.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    connectionError,
                    style: const TextStyle(color: danger, fontSize: 11),
                  ),
                ],
                const SizedBox(height: 8),
                const Text(
                  'Connect your device to the DroneESP32 Wi-Fi network first.',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CLOSE'),
            ),
            if (connected)
              FilledButton(
                onPressed: () {
                  _disconnect();
                  Navigator.pop(dialogContext);
                },
                child: const Text('DISCONNECT'),
              )
            else
              FilledButton(
                onPressed: connecting
                    ? null
                    : () {
                        final value = controller.text.trim();
                        if (value.isEmpty) return;

                        setState(() {
                          host = value;
                        });

                        Navigator.pop(dialogContext);
                        _connect();
                      },
                child: Text(connecting ? 'CONNECTING…' : 'CONNECT'),
              ),
          ],
        );
      },
    );

    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final joystickSize = (constraints.maxHeight * 0.69).clamp(
              125.0,
              330.0,
            );

            return Column(
              children: [
                _topBar(),
                Container(height: 1, color: const Color(0xFF283044)),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: _joystickArea(
                            accent: violet,
                            title: 'THROTTLE / YAW',
                            child: DroneJoystick(
                              title: 'LEFT STICK',
                              subtitle: 'THROTTLE / YAW',
                              accent: violet,
                              isThrottle: true,
                              size: joystickSize,
                              onChanged: (values) {
                                setState(() {
                                  yaw = values.x * 100;
                                  throttle = values.y;
                                });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: (constraints.maxWidth * 0.23).clamp(
                            180.0,
                            270.0,
                          ),
                          child: _centerControls(),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 4,
                          child: _joystickArea(
                            accent: mint,
                            title: 'PITCH / ROLL',
                            child: DroneJoystick(
                              title: 'RIGHT STICK',
                              subtitle: 'PITCH / ROLL',
                              accent: mint,
                              isThrottle: false,
                              size: joystickSize,
                              onChanged: (values) {
                                setState(() {
                                  roll = values.x * 100;
                                  pitch = values.y * 100;
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
      child: Row(
        children: [
          const Icon(Icons.change_history_rounded, color: violet, size: 32),
          const SizedBox(width: 9),
          const Text(
            'NOVA',
            style: TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.5,
            ),
          ),
          const SizedBox(width: 5),
          const Text(
            'FLIGHT',
            style: TextStyle(
              color: violet,
              fontSize: 21,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.5,
            ),
          ),
          const Spacer(),

          // Altitudine în HUD, fără card mare.
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                '⌃  ALT',
                style: TextStyle(
                  color: muted,
                  fontSize: 10,
                  letterSpacing: 1.4,
                ),
              ),
              Text(
                altitude == null ? '-- m' : '${altitude!.toStringAsFixed(1)} m',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),

          const Spacer(),

          // Wi-Fi: deschide meniul de conectare.
          InkWell(
            onTap: _showConnectionDialog,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF111724),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: connected
                      ? mint.withValues(alpha: 0.55)
                      : const Color(0xFF30394C),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.wifi_rounded,
                    color: connected ? mint : muted,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        connected ? 'CONNECTED' : 'WI-FI',
                        style: TextStyle(
                          color: connected ? mint : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                      Text(
                        connected ? host : 'Tap to connect',
                        style: const TextStyle(color: muted, fontSize: 9),
                      ),
                    ],
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: muted,
                    size: 17,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 14),
          const Icon(Icons.battery_5_bar_rounded, color: mint, size: 23),
          const SizedBox(width: 5),
          Text(
            battery == null ? '--' : '${battery!.toStringAsFixed(0)}%',
            style: const TextStyle(
              color: mint,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            onPressed: _showConnectionDialog,
            icon: const Icon(Icons.settings_outlined, color: muted, size: 22),
          ),
        ],
      ),
    );
  }

  Widget _joystickArea({
    required Color accent,
    required String title,
    required Widget child,
  }) {
    // Fără card în jurul joystick-ului:
    // lăsăm cercul și efectele componentei existente să iasă în evidență.
    return Column(
      children: [
        Expanded(child: Center(child: child)),
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Text(
            title,
            style: TextStyle(
              color: accent,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.0,
              shadows: [
                Shadow(color: accent.withValues(alpha: 0.45), blurRadius: 12),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _centerControls() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Simbolul dronei și starea.
        Icon(
          Icons.air,
          color: armed ? mint : violet,
          size: 46,
          shadows: [
            Shadow(
              color: (armed ? mint : violet).withValues(alpha: 0.55),
              blurRadius: 22,
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          armed
              ? (inFlight ? 'IN FLIGHT' : 'ARMED')
              : (armCommandRequested ? 'ARM CMD SENT' : 'DISARMED'),
          style: TextStyle(
            color: armed ? mint : Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
        Container(
          margin: const EdgeInsets.only(top: 13, bottom: 18),
          width: 90,
          height: 1,
          color: const Color(0xFF30394C),
        ),

        _controlButton(
          label: (armed || armCommandRequested) ? 'DISARM' : 'ARM',
          icon: (armed || armCommandRequested)
              ? Icons.lock_open_rounded
              : Icons.lock_outline_rounded,
          color: violet,
          enabled: connected && _rcConnected,
          onTap: _toggleArm,
        ),
        const SizedBox(height: 10),

        
        _controlButton(
          label: navAltHoldRequested ? 'ALT HOLD CMD ON' : 'NAV ALTHOLD',
          icon: Icons.height,
          color: navAltHoldRequested ? mint : violet,
          enabled: connected && _rcConnected,
          onTap: _toggleNavAltHold,
        ),

        const SizedBox(height: 10),
        _controlButton(
          label: inFlight ? 'LAND' : 'TAKEOFF',
          icon: inFlight
              ? Icons.flight_land_rounded
              : Icons.flight_takeoff_rounded,
          color: mint,
          enabled: false,
          onTap: _toggleFlight,
        ),

        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF111724),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF30394C)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value:
                  const [
                    'STABILIZE',
                    'ALT HOLD',
                    'POSITION',
                  ].contains(flightMode)
                  ? flightMode
                  : null,
              hint: const Text('UNKNOWN'),
              isDense: true,
              dropdownColor: panel,
              iconEnabledColor: violet,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
              items: const [
                DropdownMenuItem(value: 'STABILIZE', child: Text('STABILIZE')),
                DropdownMenuItem(value: 'ALT HOLD', child: Text('ALT HOLD')),
                DropdownMenuItem(value: 'POSITION', child: Text('POSITION')),
              ],
              onChanged: null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _controlButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 43,
      child: OutlinedButton.icon(
        onPressed: enabled ? onTap : null,
        icon: Icon(icon, size: 17),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          disabledForegroundColor: muted.withValues(alpha: 0.5),
          backgroundColor: color.withValues(alpha: 0.07),
          side: BorderSide(
            color: enabled
                ? color.withValues(alpha: 0.75)
                : muted.withValues(alpha: 0.2),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
