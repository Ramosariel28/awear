// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'connection_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$availablePortsHash() => r'acdb58f3f48c14ed6d30642576978d04ad55c9f2';

/// 1. Stream of Available Ports (Auto-refreshes)
///
/// Copied from [availablePorts].
@ProviderFor(availablePorts)
final availablePortsProvider = AutoDisposeStreamProvider<List<String>>.internal(
  availablePorts,
  name: r'availablePortsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$availablePortsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef AvailablePortsRef = AutoDisposeStreamProviderRef<List<String>>;
String _$deviceConnectionHash() => r'fe1dc80d525b83061a1b74dd551c1162eb2725a5';

/// 2. Connection State Manager
///
/// Copied from [DeviceConnection].
@ProviderFor(DeviceConnection)
final deviceConnectionProvider =
    NotifierProvider<DeviceConnection, String?>.internal(
  DeviceConnection.new,
  name: r'deviceConnectionProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$deviceConnectionHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$DeviceConnection = Notifier<String?>;
String _$packetStreamHash() => r'c4dc465f90ac84cace4aefd4f7a73ea9750e78aa';

/// 3. The Live Data Stream
/// This is what the UI will listen to!
///
/// Copied from [PacketStream].
@ProviderFor(PacketStream)
final packetStreamProvider =
    StreamNotifierProvider<PacketStream, SerialPacket>.internal(
  PacketStream.new,
  name: r'packetStreamProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$packetStreamHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$PacketStream = StreamNotifier<SerialPacket>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
