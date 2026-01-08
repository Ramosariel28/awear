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
  final SerialPortReader reader; // <--- ADDED THIS
  final StreamSubscription? subscription;
  final String? pairedToMac;

  ConnectedDevice({
    required this.portName,
    required this.type,
    required this.macAddress,
    required this.port,
    required this.reader, // <--- REQUIRED NOW
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
      _forceDisconnect(dev);
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

    // 1. CLEANUP (Handle Unplug Events)
    final toRemove = <ConnectedDevice>[];
    for (final device in _activeDevices) {
      if (!available.contains(device.portName)) {
        toRemove.add(device);
      }
    }

    if (toRemove.isNotEmpty) {
      for (final dev in toRemove) {
        print("CORE: Device unplugged: ${dev.portName}");
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

    // Attempt to open. If it fails (busy), return null immediately.
    try {
      if (!port.openReadWrite()) return null;
    } catch (e) {
      return null;
    }

    final config = SerialPortConfig();
    ProbeResult? result;
    String buffer = "";

    try {
      config.baudRate = 921600; // MUST MATCH FIRMWARE
      config.dtr = 1;
      config.rts = 1;
      port.config = config;

      // Wait for Boot/Connection stability
      await Future.delayed(const Duration(milliseconds: 1500));
      port.flush();

      // We use a temporary reader just for probing
      final reader = SerialPortReader(port, timeout: 1500);

      // Send Identify Command
      try {
        port.write(Uint8List.fromList("AWEAR_IDENTIFY\n".codeUnits));
      } catch (e) {
        // Write failed? Port probably died.
        reader.close();
        return null;
      }

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
      reader.close(); // Clean up probe reader
    } catch (e) {
      // Timeout or Error during probe
    } finally {
      config.dispose();
    }

    if (result == null) {
      // If we didn't find anything, close the port so we can try again later
      try {
        port.close();
      } catch (e) {}
      return null;
    }
    return result;
  }

  ConnectedDevice _registerDevice(ProbeResult info) {
    // 1. Reconfigure for Streaming
    final config = info.port.config;
    config.dtr = 0;
    config.rts = 0;
    info.port.config = config;
    info.port.flush();

    // 2. Create the Long-Term Reader
    final reader = SerialPortReader(info.port);

    // 3. Subscribe
    final sub = reader.stream.listen(
      (data) {
        final str = String.fromCharCodes(data);
        _handleData(info.type, str);
      },
      onError: (err) {
        // FILTER THE "UNPLUGGED" ERROR
        if (err.toString().contains("errno = 0")) {
          print("CORE: Device disconnected (Clean Unplug) on ${info.portName}");
        } else {
          print("CORE: Error on ${info.portName}: $err");
        }

        // Trigger cleanup
        _handleStreamError(info.portName);
      },
      onDone: () {
        print("CORE: Stream closed on ${info.portName}");
        _handleStreamError(info.portName);
      },
    );

    return ConnectedDevice(
      portName: info.portName,
      type: info.type,
      macAddress: info.mac,
      port: info.port,
      reader: reader, // STORE IT
      subscription: sub,
      pairedToMac: info.pairedTo,
    );
  }

  void _handleStreamError(String portName) {
    final dev = _activeDevices.where((d) => d.portName == portName).firstOrNull;
    if (dev != null) {
      _forceDisconnect(dev).then((_) {
        // Only remove from list after we successfully closed everything
        _activeDevices.remove(dev);
        _updateState();
      });
    }
  }

  Future<void> _forceDisconnect(ConnectedDevice dev) async {
    print("CORE: Cleaning up resources for ${dev.portName}...");
    try {
      // 1. Stop Listening
      await dev.subscription?.cancel();

      // 2. Kill the Reader Loop (Crucial for VSCode Exception)
      dev.reader.close();

      // 3. Yield to let OS release locks
      await Future.delayed(const Duration(milliseconds: 200));

      // 4. Close the Hardware Port
      if (dev.port.isOpen) {
        dev.port.close();
      }
      print("CORE: Disconnected ${dev.portName} successfully.");
    } catch (e) {
      print("CORE: Warning during disconnect: $e");
    }
  }

  void _updateState() {
    state = [..._activeDevices];
  }

  void _handleData(DeviceType type, String data) {
    if (type == DeviceType.receiver) {
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

    if (_serialBuffer.length > 20000) {
      print("CORE WARNING: Buffer Overflow. Clearing.");
      _serialBuffer = "";
    }

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

      _packetsReceived++;
      if (_packetsReceived % 50 == 0) {
        print(
          "CORE STATUS: $_packetsReceived packets processed. Last: ${packet.sender} | HR: ${packet.heartRate}",
        );
      }
    } catch (e) {
      // Ignore parse errors
    }
  }

  Future<void> pairSender(String receiverMac) async {
    final senderDev = state.firstWhere((d) => d.type == DeviceType.sender);
    final cmd = "PAIR:$receiverMac\n";
    senderDev.port.write(Uint8List.fromList(cmd.codeUnits));
  }
}
