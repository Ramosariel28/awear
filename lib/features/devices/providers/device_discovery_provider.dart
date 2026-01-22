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
  bool _isDisposed = false; // [FIX] Track disposal state

  @override
  Future<List<ConnectedDevice>> build() async {
    print("CORE: Device Manager Started");
    _isDisposed = false;

    await Future.delayed(const Duration(milliseconds: 3000));
    await _loadBlacklist();
    await _checkForPortChanges(notify: false);
    _startScanning();

    ref.onDispose(() {
      _isDisposed = true;
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

  Future<void> _handlePortFailure(
    String portName, {
    bool permanent = false,
  }) async {
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
        dev.reader.close(); // Closes the isolate
        if (dev.port.isOpen) dev.port.close();
      } catch (e) {
        // Ignore errors during shutdown
      }
    }
    _activeDevices.clear();
  }

  void _startScanning() {
    _scanTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_isDisposed) return;
      await _checkForPortChanges(notify: true);
    });
  }

  Future<void> _checkForPortChanges({bool notify = true}) async {
    if (_isDisposed) return;

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
    if (_isDisposed) return;

    final port = SerialPort(portName);
    // [FIX] Declare reader OUTSIDE try block so catch can close it
    SerialPortReader? reader;

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

      // Initialize Reader
      reader = SerialPortReader(port, timeout: 0);

      final device = ConnectedDevice(
        portName: portName,
        type: DeviceType.unknown,
        port: port,
        reader: reader, // reader is not null here
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

      // Handshake
      Future.delayed(const Duration(seconds: 2), () {
        if (_isDisposed) return;
        if (_activeDevices.contains(device) &&
            device.type == DeviceType.unknown) {
          try {
            port.write(Uint8List.fromList("AWEAR_IDENTIFY\n".codeUnits));
          } catch (e) {
            _forceDisconnect(device);
          }
        }
      });

      Future.delayed(const Duration(seconds: 6), () {
        if (_isDisposed) return;
        if (_activeDevices.contains(device) &&
            device.type == DeviceType.unknown) {
          _forceDisconnect(device);
          _handlePortFailure(portName);
        }
      });
    } catch (e) {
      // [FIX] Cleanup if initialization fails halfway
      try {
        reader?.close(); // Kill the zombie isolate!
        port.close();
      } catch (_) {}
      _handlePortFailure(portName);
    }
  }

  void _handleRawData(ConnectedDevice device, String chunk) {
    _parseLines(device, chunk);

    if (device.type == DeviceType.unknown) {
      device.identityBuffer += chunk;
      if (device.identityBuffer.length > 1024) {
        device.identityBuffer = device.identityBuffer.substring(
          device.identityBuffer.length - 1024,
        );
      }

      if (device.identityBuffer.contains("AWEAR_RECEIVER")) {
        device.type = DeviceType.receiver;
        _updateState();
      } else if (device.identityBuffer.contains("AWEAR_SENDER")) {
        device.type = DeviceType.sender;
        _updateState();
      }
    }

    if (device.type == DeviceType.sender) {
      if (chunk.contains("PAIRED_OK")) {
        ref.read(pairingStatusProvider.notifier).setSuccess();
        final currentReceiver = state.value
            ?.where((d) => d.type == DeviceType.receiver)
            .firstOrNull;
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
    if (!_isDisposed) {
      state = AsyncValue.data([..._activeDevices]);
    }
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

      if (json.containsKey('device') && json.containsKey('mac')) {
        final devTypeStr = json['device'].toString();
        if (devTypeStr == 'AWEAR_RECEIVER') {
          device.type = DeviceType.receiver;
        } else if (devTypeStr == 'AWEAR_SENDER') {
          device.type = DeviceType.sender;
        }

        final mac = json['mac'].toString();
        if (mac.isNotEmpty) {
          print("CORE: Captured MAC for ${device.portName}: $mac");
          device.macAddress = mac;
        }
        _updateState();
        return;
      }

      if (json.containsKey('device')) return;

      final packet = SerialPacket.fromJson(json);

      if (packet.sender != null && device.macAddress == "Unknown") {
        device.macAddress = packet.sender;
        _updateState();
      }

      ref.read(packetStreamProvider.notifier).emit(packet);

      _packetsReceived++;
      if (_packetsReceived % 50 == 0) {
        print("CORE STATUS: $_packetsReceived packets.");
      }
    } catch (e) {
      // Ignore
    }
  }

  Future<void> pairSender(String receiverMac) async {
    final senderDev = state.value
        ?.where((d) => d.type == DeviceType.sender)
        .firstOrNull;
    if (senderDev != null) {
      final cmd = "PAIR:$receiverMac\n";
      print("CORE: Sending pair command: $cmd");
      senderDev.port.write(Uint8List.fromList(cmd.codeUnits));
    } else {
      print("CORE: Cannot pair - Sender device not found.");
    }
  }
}
