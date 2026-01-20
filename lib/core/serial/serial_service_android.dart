import 'dart:async';
import 'dart:typed_data';
import 'package:usb_serial/usb_serial.dart';
import 'serial_service_contract.dart';

class SerialServiceAndroid implements SerialServiceContract {
  UsbPort? _port;
  final _dataController = StreamController<String>.broadcast();
  bool _isConnected = false;

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<String> get dataStream => _dataController.stream;

  @override
  Stream<List<String>> getAvailablePorts() {
    // usb_serial provides a stream of events when devices are attached/detached
    // We map that to a list of device names
    return UsbSerial.usbEventStream?.asyncMap((_) async {
          final devices = await UsbSerial.listDevices();
          return devices.map((d) => d.deviceName).toList();
        }) ??
        Stream.value([]);
  }

  // Note: On Android, "portName" is often not unique enough,
  // but for simplicity, we will match by device name.
  @override
  Future<void> connect(String portName) async {
    if (_isConnected) await disconnect();

    final devices = await UsbSerial.listDevices();
    final device = devices.firstWhere(
      (d) => d.deviceName == portName,
      orElse: () => throw Exception("Device not found"),
    );

    _port = await device.create();

    // Critical: Android requires permission popup
    bool openResult = await _port!.open();
    if (!openResult) {
      throw Exception("Failed to open port. Permission denied?");
    }

    await _port!.setDTR(true);
    await _port!.setRTS(true);
    await _port!.setPortParameters(
      921600,
      UsbPort.DATABITS_8,
      UsbPort.STOPBITS_1,
      UsbPort.PARITY_NONE,
    );

    _isConnected = true;

    // Listen to data
    _port!.inputStream?.listen((Uint8List data) {
      final stringData = String.fromCharCodes(data);
      _dataController.add(stringData);
    });
  }

  @override
  Future<void> disconnect() async {
    await _port?.close();
    _port = null;
    _isConnected = false;
  }

  @override
  Future<void> sendCommand(String data) async {
    if (!_isConnected || _port == null) return;
    final bytes = Uint8List.fromList(data.codeUnits);
    await _port!.write(bytes);
  }
}
