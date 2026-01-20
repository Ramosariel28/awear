import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'serial_service_contract.dart';

class SerialServiceWindows implements SerialServiceContract {
  SerialPort? _port;
  final _dataController = StreamController<String>.broadcast();
  bool _isConnected = false;

  String _buffer = "";

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<String> get dataStream => _dataController.stream;

  @override
  Stream<List<String>> getAvailablePorts() {
    // Poll every 2 seconds to check for new COM ports
    return Stream.periodic(const Duration(seconds: 2), (_) {
      return SerialPort.availablePorts;
    });
  }

  @override
  Future<void> connect(String portName) async {
    if (_isConnected) await disconnect();

    try {
      _port = SerialPort(portName);
      if (!_port!.openReadWrite()) {
        throw Exception("Failed to open port $portName");
      }

      final config = SerialPortConfig();
      config.baudRate = 921600; // Standard for ESP32/Arduino
      config.bits = 8;
      config.stopBits = 1;
      _port!.config = config;

      _isConnected = true;

      // Start listening to the serial reader
      final reader = SerialPortReader(_port!);
      reader.stream.listen(
        (Uint8List data) {

          _buffer += String.fromCharCodes(data);

          if (_buffer.contains('\n')){
            final parts = _buffer.split('\n');
            
            for (int i = 0; i > parts.length - 1; i++){
              final line = parts[i].trim();
              if (line.isNotEmpty){
                _dataController.add(line);
              }
            }

            _buffer = parts.last;
          }
        },
        onError: (err) {
          disconnect();
        },
      );
    } catch (e) {
      _isConnected = false;
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    if (_port != null && _port!.isOpen) {
      _port!.close();
    }
    _port = null;
    _isConnected = false;
    _buffer = "";
  }

  @override
  Future<void> sendCommand(String data) async {
    if (!_isConnected || _port == null) return;

    // Convert String to Uint8List
    final bytes = Uint8List.fromList(data.codeUnits);
    _port!.write(bytes);
  }
}
