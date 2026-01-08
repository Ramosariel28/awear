import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/serial/serial_packet.dart';
import 'connection_provider.dart';

part 'device_discovery_provider.g.dart';

enum DeviceType { receiver, sender, unknown }

class ConnectedDevice {
  final String portName;
  final DeviceType type;
  final String macAddress;
  final SerialPort port;
  final StreamSubscription? subscription;
  final String? pairedToMac;

  ConnectedDevice({
    required this.portName,
    required this.type,
    required this.macAddress,
    required this.port,
    this.subscription,
    this.pairedToMac,
  });
}

class ProbeResult {
  final String portName;
  final SerialPort port;
  final DeviceType type;
  final String mac;
  final String? pairedTo;

  ProbeResult(this.portName, this.port, this.type, this.mac, {this.pairedTo});
}

@riverpod
class PairingStatus extends _$PairingStatus {
  @override
  String? build() => null;
  void setSuccess() {
    state = "Success";
    Future.delayed(const Duration(seconds: 3), () => state = null);
  }
}

@Riverpod(keepAlive: true)
class DeviceManager extends _$DeviceManager {
  Timer? _scanTimer;
  final List<ConnectedDevice> _activeDevices = [];
  final Set<String> _checkedPorts = {};

  // BUFFER & METRICS
  String _serialBuffer = "";
  int _packetsReceived = 0;

  @override
  List<ConnectedDevice> build() {
    print("CORE: Device Manager Started");
    _startScanning();
    ref.onDispose(() {
      _scanTimer?.cancel();
      _closeAll();
    });
    return [];
  }

  void _closeAll() {
    for (final dev in _activeDevices) {
      dev.subscription?.cancel();
      dev.port.close();
    }
  }

  ConnectedDevice? get receiver =>
      state.where((d) => d.type == DeviceType.receiver).firstOrNull;
  ConnectedDevice? get sender =>
      state.where((d) => d.type == DeviceType.sender).firstOrNull;

  void _startScanning() {
    _scanTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      await _scanForNewPorts();
    });
  }

  Future<void> _scanForNewPorts() async {
    final available = SerialPort.availablePorts.toSet();

    // 1. CLEANUP
    final toRemove = <ConnectedDevice>[];
    for (final device in _activeDevices) {
      if (!available.contains(device.portName)) {
        toRemove.add(device);
      }
    }

    if (toRemove.isNotEmpty) {
      for (final dev in toRemove) {
        print("CORE: Device removed: ${dev.portName}");
        await _forceDisconnect(dev);
      }
      _updateState();
    }

    // 2. DISCOVERY
    _checkedPorts.removeWhere((p) => !available.contains(p));
    final activeNames = _activeDevices.map((d) => d.portName).toSet();
    final candidates = available
        .where((p) => !activeNames.contains(p) && !_checkedPorts.contains(p))
        .toList();

    if (candidates.isEmpty) return;

    // 3. PROBING
    final futures = candidates.map((portName) async {
      _checkedPorts.add(portName);
      return await _probePort(portName);
    });

    final probeResults = await Future.wait(futures);

    bool added = false;
    for (final result in probeResults) {
      if (result != null) {
        print(
          "CORE: Success! Connected to ${result.type} on ${result.portName}",
        );
        final dev = _registerDevice(result);
        _activeDevices.add(dev);
        added = true;
      }
    }

    if (added) {
      _updateState();
    }
  }

  Future<ProbeResult?> _probePort(String portName) async {
    final port = SerialPort(portName);
    if (!port.openReadWrite()) return null;

    final config = SerialPortConfig();
    ProbeResult? result;
    String buffer = "";

    try {
      // HIGH SPEED CONFIGURATION (Must match ESP32)
      config.baudRate = 921600;
      config.dtr = 1;
      config.rts = 1;
      port.config = config;

      await Future.delayed(const Duration(milliseconds: 1000));
      port.flush();

      final reader = SerialPortReader(port, timeout: 1500);
      port.write(Uint8List.fromList("AWEAR_IDENTIFY\n".codeUnits));

      await for (final data in reader.stream) {
        final chunk = String.fromCharCodes(data);
        buffer += chunk;

        if (buffer.contains("{") && buffer.contains("}")) {
          final start = buffer.indexOf("{");
          final end = buffer.lastIndexOf("}");
          if (end > start) {
            final jsonStr = buffer.substring(start, end + 1);
            try {
              final json = jsonDecode(jsonStr);
              if (json['device'] == 'AWEAR_RECEIVER') {
                result = ProbeResult(
                  portName,
                  port,
                  DeviceType.receiver,
                  json['mac'],
                );
                break;
              } else if (json['device'] == 'AWEAR_SENDER') {
                result = ProbeResult(
                  portName,
                  port,
                  DeviceType.sender,
                  json['mac'],
                  pairedTo: json['paired_to'],
                );
                break;
              }
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      // Timeout
    } finally {
      config.dispose();
    }

    if (result == null) {
      port.close();
      return null;
    }
    return result;
  }

  ConnectedDevice _registerDevice(ProbeResult info) {
    // Disable Flow Control signals for raw streaming
    final config = info.port.config;
    config.dtr = 0;
    config.rts = 0;
    info.port.config = config;
    info.port.flush();

    final reader = SerialPortReader(info.port);
    final sub = reader.stream.listen(
      (data) {
        final str = String.fromCharCodes(data);
        _handleData(info.type, str);
      },
      onError: (err) {
        print("CORE: Error on ${info.portName}: $err");
        _handleStreamError(info.portName);
      },
      onDone: () {
        _handleStreamError(info.portName);
      },
    );

    return ConnectedDevice(
      portName: info.portName,
      type: info.type,
      macAddress: info.mac,
      port: info.port,
      subscription: sub,
      pairedToMac: info.pairedTo,
    );
  }

  void _handleStreamError(String portName) {
    final dev = _activeDevices.where((d) => d.portName == portName).firstOrNull;
    if (dev != null) {
      _forceDisconnect(dev).then((_) {
        _activeDevices.remove(dev);
        _updateState();
      });
    }
  }

  Future<void> _forceDisconnect(ConnectedDevice dev) async {
    try {
      await dev.subscription?.cancel();
      dev.port.close();
    } catch (e) {}
  }

  void _updateState() {
    state = [..._activeDevices];
  }

  void _handleData(DeviceType type, String data) {
    if (type == DeviceType.receiver) {
      // Use Line Parser to avoid print() blockage
      _parseLines(data);
    } else if (type == DeviceType.sender) {
      if (data.contains("PAIRED_OK")) {
        ref.read(pairingStatusProvider.notifier).setSuccess();
      }
    }
  }

  // --- EFFICIENT LINE PARSER ---
  void _parseLines(String chunk) {
    _serialBuffer += chunk;

    // Safety Cap
    if (_serialBuffer.length > 20000) {
      print("CORE WARNING: Buffer Overflow. Clearing.");
      _serialBuffer = "";
    }

    // Process all complete lines found
    while (_serialBuffer.contains('\n')) {
      final index = _serialBuffer.indexOf('\n');
      final line = _serialBuffer.substring(0, index).trim();
      _serialBuffer = _serialBuffer.substring(index + 1);

      if (line.isNotEmpty) {
        _attemptJsonParse(line);
      }
    }
  }

  void _attemptJsonParse(String jsonString) {
    try {
      final json = jsonDecode(jsonString);
      final packet = SerialPacket.fromJson(json);

      ref.read(packetStreamProvider.notifier).emit(packet);

      // LOGGING STRATEGY:
      // Only print every 50th packet.
      // FIXED: Used 'packet.heartRate' instead of 'packet.hr'
      _packetsReceived++;
      if (_packetsReceived % 50 == 0) {
        print(
          "CORE STATUS: $_packetsReceived packets processed. Last: ${packet.sender} | HR: ${packet.heartRate}",
        );
      }
    } catch (e) {
      // Minimal error logging
    }
  }

  Future<void> pairSender(String receiverMac) async {
    final senderDev = state.firstWhere((d) => d.type == DeviceType.sender);
    final cmd = "PAIR:$receiverMac\n";
    senderDev.port.write(Uint8List.fromList(cmd.codeUnits));
  }
}
