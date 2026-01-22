// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_discovery_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$pairingStatusHash() => r'7fc7dac64e6de0453f9f8c1a4b9852809bf3c29b';

/// See also [PairingStatus].
@ProviderFor(PairingStatus)
final pairingStatusProvider =
    AutoDisposeNotifierProvider<PairingStatus, String?>.internal(
  PairingStatus.new,
  name: r'pairingStatusProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$pairingStatusHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$PairingStatus = AutoDisposeNotifier<String?>;
String _$deviceManagerHash() => r'c48d2d5382d903ea027f13f5f65571861c3323ab';

/// See also [DeviceManager].
@ProviderFor(DeviceManager)
final deviceManagerProvider =
    AsyncNotifierProvider<DeviceManager, List<ConnectedDevice>>.internal(
  DeviceManager.new,
  name: r'deviceManagerProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$deviceManagerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$DeviceManager = AsyncNotifier<List<ConnectedDevice>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
