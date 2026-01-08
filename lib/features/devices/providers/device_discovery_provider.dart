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

// 1. MUTABLE CLASS: Allows updating subscription/type in place
class ConnectedDevice {
  final String portName;
  DeviceType type; // Mutable
  String macAddress; // Mutable
  final SerialPort port;
  final SerialPortReader reader;
  StreamSubscription? subscription; // Mutable
  String? pairedToMac;

  ConnectedDevice({
    required this.portName,
    required this.type,
    this.macAddress = "Unknown",
    required this.port,
    required this.reader,
    this.subscription,
    this.pairedToMac,
  });
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

  // STATE: The Snapshot of ports from the previous check
  Set<String> _lastKnownPorts = {};

  // BLACKLIST: Ports that crash or aren't ours
  final Set<String> _ignoredPorts = {};

  // BUFFER & METRICS
  String _serialBuffer = "";
  int _packetsReceived = 0;

  @override
  List<ConnectedDevice> build() {
    print("CORE: Device Manager Started (Fixed Diff Mode)");
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
    // Check every 2 seconds. Lightweight diff check.
    _scanTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      await _checkForPortChanges();
    });
  }

  Future<void> _checkForPortChanges() async {
    // 1. Get Current Snapshot
    final currentPortsList = SerialPort.availablePorts;
    final currentPorts = currentPortsList.toSet();

    // 2. Calculate Diffs
    final addedPorts = currentPorts.difference(_lastKnownPorts);
    final removedPorts = _lastKnownPorts.difference(currentPorts);

    // 3. Update Snapshot
    _lastKnownPorts = currentPorts;

    // 4. Handle REMOVED (Unplugged)
    if (removedPorts.isNotEmpty) {
      for (final portName in removedPorts) {
        final activeDev = _activeDevices
            .where((d) => d.portName == portName)
            .firstOrNull;
        if (activeDev != null) {
          print("CORE: Device unplugged: $portName");
          await _forceDisconnect(activeDev);
        }
        // Also clear from blacklist so we can retry if plugged back in
        _ignoredPorts.remove(portName);
      }
      _updateState();
    }

    // 5. Handle ADDED (Plugged In)
    if (addedPorts.isNotEmpty) {
      for (final portName in addedPorts) {
        // A. Filter Legacy/System Ports
        if (['COM1', 'COM2'].contains(portName)) continue;

        // B. Filter Blacklisted Ports
        if (_ignoredPorts.contains(portName)) continue;

        print("CORE: New port detected: $portName. Connecting...");

        // Give Windows a moment to finish driver setup
        await Future.delayed(const Duration(milliseconds: 500));

        _connectAndIdentify(portName);
      }
    }
  }

  Future<void> _connectAndIdentify(String portName) async {
    final port = SerialPort(portName);

    // Attempt Open
    try {
      if (!port.openReadWrite()) {
        print("CORE: Failed to open new port $portName");
        _ignoredPorts.add(portName); // Temporary ignore
        return;
      }
    } catch (e) {
      _ignoredPorts.add(portName);
      return;
    }

    try {
      final config = SerialPortConfig();
      config.baudRate = 921600;
      config.dtr = 1;
      config.rts = 1;
      config.bits = 8;
      config.stopBits = 1;
      config.parity = SerialPortParity.none;

      try {
        port.config = config;
      } catch (e) {
        // Error 87 = Incompatible Hardware -> Permanent Blacklist
        print("CORE: Port $portName incompatible. Ignoring forever.");
        port.close();
        _ignoredPorts.add(portName);
        return;
      }

      port.flush();

      // Create Reader
      final reader = SerialPortReader(port, timeout: 0);

      // --- CRITICAL FIX: SINGLE INSTANCE CREATION ---
      final device = ConnectedDevice(
        portName: portName,
        type: DeviceType.unknown,
        port: port,
        reader: reader,
        subscription: null, // Will assign next
      );

      // Add to list immediately so it's tracked
      _activeDevices.add(device);

      // Start Listening
      device.subscription = reader.stream.listen(
        (data) {
          final str = String.fromCharCodes(data);
          // Now checking the SAME object instance
          _handleRawData(device, str);
        },
        onError: (err) {
          if (!err.toString().contains("errno = 0")) {
            print("CORE: Error on $portName: $err");
          }
          _forceDisconnect(device);
        },
        onDone: () => _forceDisconnect(device),
      );

      // Handshake
      try {
        port.write(Uint8List.fromList("AWEAR_IDENTIFY\n".codeUnits));
      } catch (e) {
        _forceDisconnect(device);
        return;
      }

      // TIMEOUT CHECK
      // If still Unknown after 4 seconds, kill it.
      Future.delayed(const Duration(seconds: 4), () {
        // We check the device object directly since it's the same instance
        if (_activeDevices.contains(device) &&
            device.type == DeviceType.unknown) {
          print("CORE: $portName did not identify as AWEAR. Closing.");
          _forceDisconnect(device);
          _ignoredPorts.add(portName); // Prevent re-scanning this session
        }
      });
    } catch (e) {
      print("CORE: Setup crashed for $portName");
      try {
        port.close();
      } catch (_) {}
      _ignoredPorts.add(portName);
    }
  }

  void _handleRawData(ConnectedDevice device, String chunk) {
    // 1. IDENTITY CHECK (Runs until type is confirmed)
    if (device.type == DeviceType.unknown) {
      if (chunk.contains("AWEAR_RECEIVER")) {
        print("CORE: SUCCESS! Recognized RECEIVER on ${device.portName}");
        device.type = DeviceType.receiver;
        _updateState();
      } else if (chunk.contains("AWEAR_SENDER")) {
        print("CORE: SUCCESS! Recognized SENDER on ${device.portName}");
        device.type = DeviceType.sender;
        _updateState();
      }
      // Implicit Check (Fail-safe)
      else if (chunk.contains('"sender":') && chunk.contains('"rssi":')) {
        print("CORE: Implicitly recognized RECEIVER on ${device.portName}");
        device.type = DeviceType.receiver;
        _updateState();
      }
    }

    // 2. ROUTING (Runs continuously)
    if (device.type == DeviceType.receiver) {
      _parseLines(chunk);
    } else if (device.type == DeviceType.sender) {
      if (chunk.contains("PAIRED_OK")) {
        ref.read(pairingStatusProvider.notifier).setSuccess();
      }
    }
  }

  Future<void> _forceDisconnect(ConnectedDevice dev) async {
    _activeDevices.remove(dev);
    if (dev.type != DeviceType.unknown) {
      _updateState();
    }

    try {
      await dev.subscription?.cancel();
      dev.reader.close();
      if (dev.port.isOpen) dev.port.close();
    } catch (e) {}
  }

  void _updateState() {
    state = [..._activeDevices];
  }

  void _parseLines(String chunk) {
    _serialBuffer += chunk;
    if (_serialBuffer.length > 50000) _serialBuffer = "";

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
      if (json.containsKey('device')) return; // Skip status messages

      final packet = SerialPacket.fromJson(json);

      ref.read(packetStreamProvider.notifier).emit(packet);

      _packetsReceived++;
      if (_packetsReceived % 50 == 0) {
        print(
          "CORE STATUS: $_packetsReceived packets. HR: ${packet.heartRate} | RSSI: ${packet.rssi}",
        );
      }
    } catch (e) {}
  }

  Future<void> pairSender(String receiverMac) async {
    final senderDev = state
        .where((d) => d.type == DeviceType.sender)
        .firstOrNull;
    if (senderDev != null) {
      final cmd = "PAIR:$receiverMac\n";
      senderDev.port.write(Uint8List.fromList(cmd.codeUnits));
    }
  }
}
