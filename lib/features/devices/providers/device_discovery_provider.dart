import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/serial/serial_packet.dart';
import 'connection_provider.dart';

part 'device_discovery_provider.g.dart';

enum DeviceType { receiver, sender, unknown }

class ConnectedDevice {
  final String portName;
  DeviceType type;
  String macAddress;
  final SerialPort port;
  final SerialPortReader reader;
  StreamSubscription? subscription;
  String? pairedToMac;
  
  // Buffers
  String identityBuffer = ""; 
  String dataBuffer = ""; 

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
  Set<String> _lastKnownPorts = {};
  final Set<String> _ignoredPorts = {};

  int _packetsReceived = 0;

  @override
  Future<List<ConnectedDevice>> build() async {
    print("CORE: Device Manager Started");
    await Future.delayed(const Duration(milliseconds: 3000));
    await _loadBlacklist();
    await _checkForPortChanges(notify: false);
    _startScanning();

    ref.onDispose(() {
      _scanTimer?.cancel();
      _closeAll();
    });

    return [..._activeDevices];
  }

  // --- PUBLIC HELPERS ---
  ConnectedDevice? get receiver =>
      state.value?.where((d) => d.type == DeviceType.receiver).firstOrNull;

  ConnectedDevice? get sender =>
      state.value?.where((d) => d.type == DeviceType.sender).firstOrNull;

  // --- BLACKLIST LOGIC ---
  Future<void> _loadBlacklist() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? saved = prefs.getStringList('ignored_serial_ports');
    if (saved != null) {
      _ignoredPorts.addAll(saved);
    }
  }

  Future<void> _handlePortFailure(String portName, {bool permanent = false}) async {
    _ignoredPorts.add(portName);
    if (permanent) {
      print("CORE: Permanently blacklisting $portName.");
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('ignored_serial_ports') ?? [];
      if (!saved.contains(portName)) {
        saved.add(portName);
        await prefs.setStringList('ignored_serial_ports', saved);
      }
    }
  }

  // --- SCANNING LOGIC ---
  void _closeAll() {
    for (final dev in _activeDevices) {
      try {
        dev.subscription?.cancel();
        dev.reader.close();
        if (dev.port.isOpen) dev.port.close();
      } catch (e) {}
    }
    _activeDevices.clear();
  }

  void _startScanning() {
    _scanTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      await _checkForPortChanges(notify: true);
    });
  }

  Future<void> _checkForPortChanges({bool notify = true}) async {
    final currentPortsList = SerialPort.availablePorts;
    final currentPorts = currentPortsList.toSet();
    final addedPorts = currentPorts.difference(_lastKnownPorts);
    final removedPorts = _lastKnownPorts.difference(currentPorts);
    _lastKnownPorts = currentPorts;

    if (removedPorts.isNotEmpty) {
      for (final portName in removedPorts) {
        final activeDev = _activeDevices
            .where((d) => d.portName == portName)
            .firstOrNull;
        if (activeDev != null) await _forceDisconnect(activeDev);
        _ignoredPorts.remove(portName);
      }
      if (notify) _updateState();
    }

    if (addedPorts.isNotEmpty) {
      for (final portName in addedPorts) {
        if (['COM1', 'COM2'].contains(portName)) {
          _handlePortFailure(portName, permanent: true);
          continue;
        }
        if (_ignoredPorts.contains(portName)) continue;
        print("CORE: New port detected: $portName. Connecting...");
        _connectAndIdentify(portName);
      }
    }
  }

  Future<void> _connectAndIdentify(String portName) async {
    final port = SerialPort(portName);
    try {
      if (!port.openReadWrite()) {
        _handlePortFailure(portName);
        return;
      }
    } catch (e) {
      _handlePortFailure(portName);
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
        port.close();
        _handlePortFailure(portName, permanent: true);
        return;
      }

      port.flush();
      final reader = SerialPortReader(port, timeout: 0);

      final device = ConnectedDevice(
        portName: portName,
        type: DeviceType.unknown,
        port: port,
        reader: reader,
        subscription: null,
      );

      _activeDevices.add(device);
      _updateState();

      device.subscription = reader.stream.listen(
        (data) {
          final str = String.fromCharCodes(data);
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

      // Handshake with DELAY for ESP32 boot
      Future.delayed(const Duration(seconds: 2), () {
        if (_activeDevices.contains(device) && device.type == DeviceType.unknown) {
           try {
             port.write(Uint8List.fromList("AWEAR_IDENTIFY\n".codeUnits));
           } catch (e) {
             _forceDisconnect(device);
           }
        }
      });

      Future.delayed(const Duration(seconds: 6), () {
        if (_activeDevices.contains(device) && device.type == DeviceType.unknown) {
          _forceDisconnect(device);
          _handlePortFailure(portName);
        }
      });
    } catch (e) {
      try { port.close(); } catch (_) {}
      _handlePortFailure(portName);
    }
  }

  void _handleRawData(ConnectedDevice device, String chunk) {
    // 1. ALWAYS PARSE JSON (Handling Handshakes & Vitals)
    // We do this first because the Identity is now inside a JSON packet.
    _parseLines(device, chunk);

    // 2. FALLBACK RAW STRING CHECK
    // (Used for "PAIRED_OK" or legacy plain-text identification)
    if (device.type == DeviceType.unknown) {
      device.identityBuffer += chunk;
      if (device.identityBuffer.length > 1024) {
        device.identityBuffer = device.identityBuffer.substring(device.identityBuffer.length - 1024);
      }
      
      // Legacy/Fallback ID check
      if (device.identityBuffer.contains("AWEAR_RECEIVER")) {
        device.type = DeviceType.receiver;
        _updateState();
      } else if (device.identityBuffer.contains("AWEAR_SENDER")) {
        device.type = DeviceType.sender;
        _updateState();
      }
    }

    // 3. SPECIAL COMMAND RESPONSES
    if (device.type == DeviceType.sender) {
      // The Sender replies with raw text "PAIRED_OK" (not JSON)
      if (chunk.contains("PAIRED_OK")) {
        ref.read(pairingStatusProvider.notifier).setSuccess();
        final currentReceiver = state.value?.where((d) => d.type == DeviceType.receiver).firstOrNull;
        if (currentReceiver != null) {
          device.pairedToMac = currentReceiver.macAddress;
          _updateState();
        }
      }
    }
  }

  Future<void> _forceDisconnect(ConnectedDevice dev) async {
    _activeDevices.remove(dev);
    _updateState();
    try {
      await dev.subscription?.cancel();
      dev.reader.close();
      if (dev.port.isOpen) dev.port.close();
    } catch (e) {}
  }

  void _updateState() {
    state = AsyncValue.data([..._activeDevices]);
  }

  void _parseLines(ConnectedDevice device, String chunk) {
    device.dataBuffer += chunk;
    if (device.dataBuffer.length > 50000) device.dataBuffer = "";

    while (device.dataBuffer.contains('\n')) {
      final index = device.dataBuffer.indexOf('\n');
      final line = device.dataBuffer.substring(0, index).trim();
      device.dataBuffer = device.dataBuffer.substring(index + 1);

      if (line.isNotEmpty) {
        _attemptJsonParse(device, line);
      }
    }
  }

  void _attemptJsonParse(ConnectedDevice device, String jsonString) {
    try {
      final json = jsonDecode(jsonString);

      // --- [FIX] HANDSHAKE PACKET HANDLING ---
      // Expected: {"status":"Receiver Ready","device":"AWEAR_RECEIVER","mac":"..."}
      if (json.containsKey('device') && json.containsKey('mac')) {
        
        // 1. Capture Identity
        final devTypeStr = json['device'].toString();
        if (devTypeStr == 'AWEAR_RECEIVER') {
          device.type = DeviceType.receiver;
        } else if (devTypeStr == 'AWEAR_SENDER') {
          device.type = DeviceType.sender;
        }

        // 2. Capture MAC Address (CRITICAL for Pairing)
        final mac = json['mac'].toString();
        if (mac.isNotEmpty) {
          print("CORE: Captured MAC for ${device.portName}: $mac");
          device.macAddress = mac;
        }

        _updateState();
        return; // Done. Do not try to parse as Vitals.
      }

      // --- VITALS PACKET HANDLING ---
      // If it's the old format that has 'device' but NO 'mac', we skip it.
      if (json.containsKey('device')) return; 

      final packet = SerialPacket.fromJson(json);

      // (Redundant fallback: Capture MAC from vitals if missing)
      if (packet.sender != null && device.macAddress == "Unknown") {
        device.macAddress = packet.sender!;
        _updateState();
      }

      ref.read(packetStreamProvider.notifier).emit(packet);

      _packetsReceived++;
      if (_packetsReceived % 50 == 0) {
        print("CORE STATUS: $_packetsReceived packets.");
      }
    } catch (e) {
      // Ignore malformed JSON
    }
  }

  Future<void> pairSender(String receiverMac) async {
    final senderDev = state.value?.where((d) => d.type == DeviceType.sender).firstOrNull;
    if (senderDev != null) {
      // Now receiverMac should be valid (e.g. 08:92:...) instead of Unknown
      final cmd = "PAIR:$receiverMac\n";
      print("CORE: Sending pair command: $cmd");
      senderDev.port.write(Uint8List.fromList(cmd.codeUnits));
    } else {
      print("CORE: Cannot pair - Sender device not found.");
    }
  }
}