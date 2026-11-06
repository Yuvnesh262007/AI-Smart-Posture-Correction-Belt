import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

const String serviceUuid =
    '12345678-1234-1234-1234-123456789001';

const String characteristicUuid =
    '12345678-1234-1234-1234-123456789002';

void main() {
  runApp(const PostureBeltApp());
}

class PostureBeltApp extends StatelessWidget {
  const PostureBeltApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Posture Belt',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const BleConnectionPage(),
    );
  }
}

class BleConnectionPage extends StatefulWidget {
  const BleConnectionPage({super.key});

  @override
  State<BleConnectionPage> createState() => _BleConnectionPageState();
}

class _BleConnectionPageState extends State<BleConnectionPage> {
  BluetoothDevice? connectedDevice;

  BluetoothCharacteristic? postureCharacteristic;

  String status = 'Ready';

  String receivedData = '';

  bool scanning = false;
  bool connecting = false;

  // Posture history is stored locally on this phone.
  final List<Map<String, dynamic>> postureHistory = [];
  String? currentPosture;
  DateTime? currentPostureStart;

  @override
  void initState() {
    super.initState();
    _loadPostureHistory();
  }

  String? _extractPosture(String data) {
    final normalized = data.toLowerCase().replaceAll('-', '_');
    if (normalized.contains('lean_left') || normalized.contains('lean left')) {
      return 'lean_left';
    }
    if (normalized.contains('lean_right') || normalized.contains('lean right')) {
      return 'lean_right';
    }
    if (normalized.contains('slouch')) return 'slouch';
    if (normalized.contains('normal')) return 'normal';
    return null;
  }

  Future<void> _loadPostureHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('posture_history_v1');
      if (saved == null || saved.isEmpty) return;

      final decoded = jsonDecode(saved) as List<dynamic>;
      final loaded = decoded
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      if (!mounted) return;
      setState(() {
        postureHistory
          ..clear()
          ..addAll(loaded);
        // A fresh tracking interval starts only after a new label arrives.
        // This prevents time while the app was closed from being counted.
        currentPosture = null;
        currentPostureStart = null;
      });
    } catch (e) {
      debugPrint('POSTURE HISTORY LOAD ERROR: $e');
    }
  }

  Future<void> _savePostureHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('posture_history_v1', jsonEncode(postureHistory));
    } catch (e) {
      debugPrint('POSTURE HISTORY SAVE ERROR: $e');
    }
  }

  void _handleIncomingData(String text) {
    final detectedPosture = _extractPosture(text);
    var historyChanged = false;

    setState(() {
      receivedData = text;

      if (detectedPosture == null) return;

      final now = DateTime.now();
      if (currentPostureStart == null) {
        // First recognised label in this app session. Start a fresh interval,
        // rather than assuming the posture persisted while the app was closed.
        currentPosture = detectedPosture;
        currentPostureStart = now;
        postureHistory.add({
          'posture': detectedPosture,
          'at': now.toIso8601String(),
          'durationSeconds': 0,
        });
        historyChanged = true;
      } else if (detectedPosture != currentPosture) {
        // Close the previous interval and log only state transitions.
        final elapsed = now.difference(currentPostureStart!).inSeconds;
        postureHistory.last['durationSeconds'] = elapsed < 0 ? 0 : elapsed;

        currentPosture = detectedPosture;
        currentPostureStart = now;
        postureHistory.add({
          'posture': detectedPosture,
          'at': now.toIso8601String(),
          'durationSeconds': 0,
        });
        historyChanged = true;
      }

      // Keep the local history bounded while retaining recent events.
      if (postureHistory.length > 500) {
        postureHistory.removeRange(0, postureHistory.length - 500);
      }
    });

    if (historyChanged) _savePostureHistory();
  }

  Duration _durationForPosture(String posture) {
    var totalSeconds = 0;
    for (var i = 0; i < postureHistory.length; i++) {
      final event = postureHistory[i];
      if (event['posture'] == posture) {
        totalSeconds += (event['durationSeconds'] as num?)?.toInt() ?? 0;
      }
    }

    if (postureHistory.isNotEmpty &&
        postureHistory.last['posture'] == posture &&
        currentPostureStart != null) {
      final liveSeconds = DateTime.now().difference(currentPostureStart!).inSeconds;
      if (liveSeconds > 0) totalSeconds += liveSeconds;
    }
    return Duration(seconds: totalSeconds);
  }

  Duration get _totalTrackedDuration {
    var totalSeconds = 0;
    for (final event in postureHistory) {
      totalSeconds += (event['durationSeconds'] as num?)?.toInt() ?? 0;
    }

    if (currentPostureStart != null) {
      final liveSeconds = DateTime.now().difference(currentPostureStart!).inSeconds;
      if (liveSeconds > 0) totalSeconds += liveSeconds;
    }
    return Duration(seconds: totalSeconds);
  }

  String _formatTrackedDuration(Duration duration) {
    if (duration.inSeconds < 60) return '${duration.inSeconds}s';
    if (duration.inMinutes < 60) return '${duration.inMinutes}m';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
  }

  String _postureTitle(String posture) {
    switch (posture) {
      case 'normal':
        return 'Normal';
      case 'slouch':
        return 'Slouch';
      case 'lean_left':
        return 'Lean Left';
      case 'lean_right':
        return 'Lean Right';
      default:
        return posture;
    }
  }

  @override
  void dispose() {
    if (currentPostureStart != null && postureHistory.isNotEmpty) {
      final elapsed = DateTime.now().difference(currentPostureStart!).inSeconds;
      postureHistory.last['durationSeconds'] = elapsed < 0 ? 0 : elapsed;
      _savePostureHistory();
    }
    super.dispose();
  }

  Future<void> scanAndConnect() async {
    try {
      setState(() {
        scanning = true;
        connecting = false;
        status = 'Scanning...';
      });

      await FlutterBluePlus.startScan(
        withNames: ['POSTURE_BELT'],
        timeout: const Duration(seconds: 10),
      );

      final results = await FlutterBluePlus.onScanResults
          .firstWhere((results) => results.isNotEmpty);

      await FlutterBluePlus.stopScan();

      ScanResult? belt;

      for (final result in results) {
        final name = result.advertisementData.advName;

        if (name == 'POSTURE_BELT') {
          belt = result;
          break;
        }
      }

      if (belt == null) {
        setState(() {
          scanning = false;
          status = 'POSTURE_BELT not found';
        });
        return;
      }

      setState(() {
        scanning = false;
        connecting = true;
        status = 'Connecting to POSTURE_BELT...';
      });

      final device = belt.device;

      await device.connect(
  license: License.nonprofit,
  timeout: const Duration(seconds: 10),
);

      connectedDevice = device;

      setState(() {
        connecting = false;
        status = 'Connected! Discovering services...';
      });

      final services = await device.discoverServices();

      BluetoothCharacteristic? foundCharacteristic;

      for (final service in services) {
        debugPrint('SERVICE: ${service.uuid}');

        for (final characteristic in service.characteristics) {
          debugPrint(
            'CHARACTERISTIC: ${characteristic.uuid}',
          );

          if (service.uuid.toString().toLowerCase() ==
                  serviceUuid.toLowerCase() &&
              characteristic.uuid.toString().toLowerCase() ==
                  characteristicUuid.toLowerCase()) {
            foundCharacteristic = characteristic;
          }
        }
      }

      if (foundCharacteristic == null) {
        setState(() {
          status = 'Connected, but characteristic not found';
        });
        return;
      }

      postureCharacteristic = foundCharacteristic;

      setState(() {
        status = 'Connected & characteristic found!';
      });

      await foundCharacteristic.setNotifyValue(true);

// Read the current value immediately.
try {
  final value = await foundCharacteristic.read();

  if (mounted && value.isNotEmpty) {
    final text = String.fromCharCodes(value);

    _handleIncomingData(text);

    debugPrint('BLE READ DATA: $text');
  }
} catch (e) {
  debugPrint('BLE READ ERROR: $e');
}

// Continue listening for future notifications.
foundCharacteristic.lastValueStream.listen(
  (value) {
    if (!mounted || value.isEmpty) return;

    final text = String.fromCharCodes(value);

    _handleIncomingData(text);

    debugPrint('BLE NOTIFICATION: $text');
  },
);

      setState(() {
        status = 'Connected & listening for posture data';
      });
    } catch (e) {
      setState(() {
        scanning = false;
        connecting = false;
        status = 'Error: $e';
      });

      debugPrint('BLE ERROR: $e');
    }
  }


  Widget _buildHistoryAnalysis(ThemeData theme, ColorScheme colors) {
    final normalDuration = _durationForPosture('normal');
    final slouchDuration = _durationForPosture('slouch');
    final leftDuration = _durationForPosture('lean_left');
    final rightDuration = _durationForPosture('lean_right');
    final poorDuration = slouchDuration + leftDuration + rightDuration;
    final totalDuration = _totalTrackedDuration;
    final totalSeconds = totalDuration.inSeconds;
    final score = totalSeconds == 0
        ? 0.0
        : (normalDuration.inSeconds / totalSeconds).clamp(0.0, 1.0).toDouble();
    final recentEvents = postureHistory.reversed.take(6).toList();
    final cardColor = theme.brightness == Brightness.dark
        ? AppColors.darkSurface
        : AppColors.lightSurface;
    final borderColor = theme.brightness == Brightness.dark
        ? AppColors.darkBorder
        : AppColors.lightBorder;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'POSTURE SCORE',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurface.withOpacity(0.58),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      totalSeconds == 0 ? '--' : '${(score * 100).round()}%',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppColors.forestOlive,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${postureHistory.length} changes logged',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurface.withOpacity(0.58),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: score,
              minHeight: 9,
              backgroundColor: colors.onSurface.withOpacity(0.09),
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.sageGreen),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            totalSeconds == 0
                ? 'Waiting for a recognised posture label to begin analysis.'
                : 'Based on time spent in recognised posture states during this tracking history.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurface.withOpacity(0.58),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _AnalysisMetric(
                  label: 'GOOD POSTURE',
                  value: _formatTrackedDuration(normalDuration),
                  color: AppColors.sageGreen,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _AnalysisMetric(
                  label: 'NEEDS CORRECTION',
                  value: _formatTrackedDuration(poorDuration),
                  color: const Color(0xFFD97969),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _AnalysisMetric(
                  label: 'SLOUCH',
                  value: _formatTrackedDuration(slouchDuration),
                  color: colors.secondary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _AnalysisMetric(
                  label: 'LEFT / RIGHT LEAN',
                  value: _formatTrackedDuration(leftDuration + rightDuration),
                  color: colors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text(
                'RECENT HISTORY',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9,
                ),
              ),
              const Spacer(),
              Text(
                'Latest first',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurface.withOpacity(0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (recentEvents.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'No posture history yet. Connect the belt and wait for a posture label.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurface.withOpacity(0.58),
                  height: 1.4,
                ),
              ),
            )
          else
            ...recentEvents.map((event) {
              final posture = event['posture'] as String? ?? 'unknown';
              final timestamp = DateTime.tryParse(event['at'] as String? ?? '');
              final isGood = posture == 'normal';
              final iconColor = isGood
                  ? AppColors.sageGreen
                  : const Color(0xFFD97969);
              final timeLabel = timestamp == null
                  ? 'Time unavailable'
                  : '${timestamp.day.toString().padLeft(2, '0')}/'
                    '${timestamp.month.toString().padLeft(2, '0')} '
                    '${timestamp.hour.toString().padLeft(2, '0')}:'
                    '${timestamp.minute.toString().padLeft(2, '0')}';

              return Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: iconColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        isGood ? Icons.thumb_up_alt_rounded : Icons.warning_amber_rounded,
                        color: iconColor,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _postureTitle(posture),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      timeLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurface.withOpacity(0.55),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isConnected = connectedDevice != null;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: _AnimatedAmbientBackground(
              isDark: theme.brightness == Brightness.dark,
            ),
          ),
          SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Brand header
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: theme.brightness == Brightness.dark
                              ? AppColors.darkElevated
                              : AppColors.cream,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Icon(
                          Icons.accessibility_new_rounded,
                          color: colors.primary,
                          size: 27,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'POSTURE BELT',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                          ),
                          Text(
                            'YOUR POSTURE COMPANION',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onSurface.withOpacity(0.58),
                              letterSpacing: 1.05,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      _ConnectionBadge(isConnected: isConnected),
                    ],
                  ),

                  const SizedBox(height: 34),

                  Text(
                    'POSTURE MONITORING',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.secondary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.45,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    'Stay aligned.\nFeel your best.',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.12,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Connect your wearable to receive live posture feedback.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colors.onSurface.withOpacity(0.67),
                      height: 1.45,
                    ),
                  ),

                  const SizedBox(height: 26),

                  // Hero card: reserved for the Phase 2 3D model.
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: theme.brightness == Brightness.dark
                            ? const [
                                AppColors.forestOlive,
                                AppColors.deepForest,
                              ]
                            : const [
                                AppColors.forestOlive,
                                AppColors.sageGreen,
                              ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.deepForest.withOpacity(
                            theme.brightness == Brightness.dark ? 0.22 : 0.12,
                          ),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.sensors_rounded,
                              color: AppColors.cream,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'LIVE DEVICE',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: AppColors.cream.withOpacity(0.84),
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.3,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.cream.withOpacity(0.14),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(
                                  color: AppColors.cream.withOpacity(0.24),
                                ),
                              ),
                              child: Text(
                                isConnected ? 'ONLINE' : 'NOT CONNECTED',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: AppColors.cream,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        Builder(
                          builder: (context) {
                            final data = receivedData
                                .toLowerCase()
                                .replaceAll('-', '_');

                            final isNormal = data.contains('normal');
                            final isSlouch = data.contains('slouch');
                            final isLeanLeft = data.contains('lean_left') ||
                                data.contains('lean left');
                            final isLeanRight = data.contains('lean_right') ||
                                data.contains('lean right');
                            final isPoorPosture =
                                isSlouch || isLeanLeft || isLeanRight;
                            final character = isNormal
                                ? '😃👍'
                                : isPoorPosture
                                    ? '😞👎'
                                    : '😐';
                            final accentColor = isNormal
                                ? const Color(0xFFB8F5C5)
                                : isPoorPosture
                                    ? const Color(0xFFFFB4A9)
                                    : AppColors.cream;
                            final postureLabel = isNormal
                                ? 'NORMAL POSTURE'
                                : isSlouch
                                    ? 'SLOUCH DETECTED'
                                    : isLeanLeft
                                        ? 'LEFT LEAN DETECTED'
                                        : isLeanRight
                                            ? 'RIGHT LEAN DETECTED'
                                            : 'POSTURE STATUS';
                            final headline = isNormal
                                ? 'GREAT POSTURE!'
                                : isPoorPosture
                                    ? 'STRAIGHTEN UP!'
                                    : 'WAITING FOR POSTURE';
                            final description = isNormal
                                ? 'Keep it up! Your posture looks good.'
                                : isPoorPosture
                                    ? 'Adjust your posture and bring your upper body back into alignment.'
                                    : receivedData.isEmpty
                                        ? 'Waiting for posture data from your wearable.'
                                        : 'Sensor data received. Waiting for a posture label.';

                            return Column(
                              children: [
                                Center(
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 350),
                                    child: Container(
                                      key: ValueKey(character),
                                      width: 148,
                                      height: 148,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: AppColors.cream.withOpacity(0.10),
                                        border: Border.all(
                                          color: accentColor.withOpacity(0.55),
                                          width: 1.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: accentColor.withOpacity(0.16),
                                            blurRadius: 25,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        character,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 66),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Center(
                                  child: Text(
                                    postureLabel,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: accentColor,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Center(
                                  child: Text(
                                    headline,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      color: accentColor,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Center(
                                  child: Text(
                                    description,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: AppColors.cream.withOpacity(0.82),
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),

                  // Connection control
                  _SectionHeading(
                    title: 'Device connection',
                    subtitle: 'Pair with your Posture Belt over Bluetooth.',
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: theme.brightness == Brightness.dark
                          ? AppColors.darkSurface
                          : AppColors.lightSurface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: theme.brightness == Brightness.dark
                            ? AppColors.darkBorder
                            : AppColors.lightBorder,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: colors.primary.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Icon(
                                isConnected
                                    ? Icons.bluetooth_connected_rounded
                                    : Icons.bluetooth_rounded,
                                color: colors.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'POSTURE_BELT',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    status,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.onSurface.withOpacity(0.62),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              isConnected
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              color: isConnected
                                  ? AppColors.sageGreen
                                  : colors.onSurface.withOpacity(0.35),
                            ),
                          ],
                        ),
                        const SizedBox(height: 17),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: scanning || connecting
                                ? null
                                : scanAndConnect,
                            icon: Icon(
                              scanning || connecting
                                  ? Icons.hourglass_top_rounded
                                  : Icons.bluetooth_searching_rounded,
                              size: 19,
                            ),
                            label: Text(
                              scanning
                                  ? 'SCANNING FOR BELT'
                                  : connecting
                                      ? 'CONNECTING'
                                      : isConnected
                                          ? 'SCAN / CONNECT AGAIN'
                                          : 'CONNECT TO POSTURE BELT',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),

                  // Raw data panel preserved for BLE verification.
                  _SectionHeading(
                    title: 'Latest device message',
                    subtitle: 'The most recent data received over BLE.',
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: theme.brightness == Brightness.dark
                          ? AppColors.darkElevated
                          : const Color(0xFFF0F4EA),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: theme.brightness == Brightness.dark
                            ? AppColors.darkBorder
                            : AppColors.lightBorder,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.sensors_rounded,
                          color: colors.secondary,
                          size: 20,
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: SelectableText(
                            receivedData.isEmpty
                                ? 'Waiting for data from your wearable...'
                                : receivedData,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              height: 1.45,
                              color: receivedData.isEmpty
                                  ? colors.onSurface.withOpacity(0.56)
                                  : colors.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 22),

                  _SectionHeading(
                    title: 'History & analysis',
                    subtitle: 'Your posture patterns based on labels received from the belt.',
                  ),
                  const SizedBox(height: 12),
                  _buildHistoryAnalysis(theme, colors),

                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      'MOVE BETTER  •  STAND TALLER',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurface.withOpacity(0.48),
                        letterSpacing: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedAmbientBackground extends StatefulWidget {
  const _AnimatedAmbientBackground({required this.isDark});

  final bool isDark;

  @override
  State<_AnimatedAmbientBackground> createState() =>
      _AnimatedAmbientBackgroundState();
}

class _AnimatedAmbientBackgroundState
    extends State<_AnimatedAmbientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _AmbientBackgroundPainter(
              progress: _controller.value,
              isDark: widget.isDark,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

class _AmbientBackgroundPainter extends CustomPainter {
  const _AmbientBackgroundPainter({
    required this.progress,
    required this.isDark,
  });

  final double progress;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final basePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? const [
                Color(0xFF06120F),
                Color(0xFF0B201B),
                Color(0xFF171C16),
              ]
            : const [
                Color(0xFFF1F8F2),
                Color(0xFFF4F8F4),
                Color(0xFFF8F5EB),
              ],
      ).createShader(rect);
    canvas.drawRect(rect, basePaint);

    final phase = progress * 2 * math.pi;
    final shortestSide = math.min(size.width, size.height);

    // Brighter, more concentrated colour pools make the aurora visible around
    // the dashboard cards while keeping the centre of the screen readable.
    void drawGlow(Offset center, double radius, Color color) {
      final glowPaint = Paint()
        ..blendMode = BlendMode.screen
        ..shader = RadialGradient(
          colors: [
            color.withOpacity(isDark ? 0.54 : 0.48),
            color.withOpacity(isDark ? 0.30 : 0.27),
            color.withOpacity(isDark ? 0.10 : 0.12),
            color.withOpacity(0.0),
          ],
          stops: const [0.0, 0.34, 0.70, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, glowPaint);
    }

    // Main emerald glow at the upper-left edge.
    drawGlow(
      Offset(
        size.width * (0.02 + 0.13 * math.sin(phase)),
        size.height * (0.17 + 0.09 * math.cos(phase * 0.9)),
      ),
      shortestSide * 0.57,
      isDark ? const Color(0xFF19D879) : const Color(0xFF42B96B),
    );

    // Teal glow travels down the right side.
    drawGlow(
      Offset(
        size.width * (1.02 + 0.12 * math.cos(phase * 0.78)),
        size.height * (0.49 + 0.15 * math.sin(phase * 0.92)),
      ),
      shortestSide * 0.58,
      isDark ? const Color(0xFF10C8C2) : const Color(0xFF42BDB2),
    );

    // Warm olive/gold glow rises from the bottom edge.
    drawGlow(
      Offset(
        size.width * (0.48 + 0.16 * math.sin(phase * 0.62 + 1.1)),
        size.height * (1.02 + 0.08 * math.cos(phase * 0.7)),
      ),
      shortestSide * 0.62,
      isDark ? const Color(0xFFB7B83B) : const Color(0xFFD1AD45),
    );

    // A cool violet accent gives the background a richer, layered look.
    drawGlow(
      Offset(
        size.width * (0.96 + 0.07 * math.sin(phase * 0.55 + 2.0)),
        size.height * (0.08 + 0.07 * math.cos(phase * 0.8)),
      ),
      shortestSide * 0.40,
      isDark ? const Color(0xFF7865D8) : const Color(0xFF9B8BE0),
    );

    // Soft moving aurora ribbons. Their edges are blurred so they read as
    // atmospheric light rather than hard shapes or foreground decorations.
    final ribbonPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = shortestSide * 0.15
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, shortestSide * 0.075)
      ..color = (isDark ? const Color(0xFF32D6A0) : const Color(0xFF69B982))
          .withOpacity(isDark ? 0.20 : 0.17);
    final ribbon = Path()
      ..moveTo(-size.width * 0.18, size.height * (0.34 + 0.06 * math.sin(phase)))
      ..cubicTo(
        size.width * 0.28,
        size.height * (0.12 + 0.10 * math.cos(phase)),
        size.width * 0.56,
        size.height * (0.55 + 0.08 * math.sin(phase * 0.8)),
        size.width * 1.18,
        size.height * (0.25 + 0.07 * math.cos(phase * 0.7)),
      );
    canvas.drawPath(ribbon, ribbonPaint);

    final secondRibbonPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = shortestSide * 0.11
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, shortestSide * 0.06)
      ..color = (isDark ? const Color(0xFF22AFAF) : const Color(0xFF78C8C1))
          .withOpacity(isDark ? 0.16 : 0.15);
    final secondRibbon = Path()
      ..moveTo(-size.width * 0.12, size.height * (0.76 + 0.05 * math.cos(phase)))
      ..cubicTo(
        size.width * 0.34,
        size.height * (0.58 + 0.08 * math.sin(phase * 0.85)),
        size.width * 0.72,
        size.height * (0.94 + 0.05 * math.cos(phase * 0.65)),
        size.width * 1.12,
        size.height * (0.66 + 0.08 * math.sin(phase * 0.75)),
      );
    canvas.drawPath(secondRibbon, secondRibbonPaint);

    // Small luminous particles drift slowly at the edges of the screen.
    // Fixed seeds keep their placement stable; only their positions and glow
    // pulse with the animation cycle.
    for (var i = 0; i < 18; i++) {
      final seed = i.toDouble();
      final xBase = ((i * 37) % 101) / 100.0;
      final yBase = ((i * 61 + 17) % 103) / 102.0;
      final x = size.width * (xBase + 0.018 * math.sin(phase + seed * 0.7));
      final y = size.height * (yBase + 0.014 * math.cos(phase * 0.8 + seed));
      final pulse = 0.5 + 0.5 * math.sin(phase * 1.4 + seed);
      final particlePaint = Paint()
        ..color = (isDark ? const Color(0xFFB7F5D2) : const Color(0xFF4A9970))
            .withOpacity((isDark ? 0.13 : 0.11) + pulse * 0.12);
      canvas.drawCircle(
        Offset(x, y),
        1.2 + pulse * 1.8,
        particlePaint,
      );
    }

    // More visible, slowly breathing halo rings in the upper-right corner.
    final ringCenter = Offset(
      size.width * (0.78 + 0.035 * math.sin(phase * 0.8)),
      size.height * (0.16 + 0.035 * math.cos(phase)),
    );
    for (var i = 0; i < 3; i++) {
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = i == 0 ? 1.8 : 1.2
        ..color = (isDark ? const Color(0xFFC4F6D8) : const Color(0xFF477A59))
            .withOpacity((isDark ? 0.10 : 0.11) - i * 0.018);
      canvas.drawCircle(
        ringCenter,
        shortestSide * (0.17 + i * 0.095) + 5 * math.sin(phase + i),
        ringPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AmbientBackgroundPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isDark != isDark;
  }
}

class _AnalysisMetric extends StatelessWidget {
  const _AnalysisMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.45,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge({required this.isConnected});

  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = isConnected
        ? AppColors.forestOlive
        : theme.colorScheme.onSurface.withOpacity(0.65);
    final background = isConnected
        ? AppColors.softSage.withOpacity(0.55)
        : theme.colorScheme.onSurface.withOpacity(0.07);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: isConnected ? AppColors.sageGreen : foreground,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            isConnected ? 'CONNECTED' : 'OFFLINE',
            style: theme.textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.62),
          ),
        ),
      ],
    );
  }
}
