// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'live_data_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$vitalHistoryHash() => r'c1dc81c28758d86e6dbf417365da916249c3ab87';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

/// See also [vitalHistory].
@ProviderFor(vitalHistory)
const vitalHistoryProvider = VitalHistoryFamily();

/// See also [vitalHistory].
class VitalHistoryFamily extends Family<AsyncValue<List<VitalLogEntity>>> {
  /// See also [vitalHistory].
  const VitalHistoryFamily();

  /// See also [vitalHistory].
  VitalHistoryProvider call(
    int userId,
  ) {
    return VitalHistoryProvider(
      userId,
    );
  }

  @override
  VitalHistoryProvider getProviderOverride(
    covariant VitalHistoryProvider provider,
  ) {
    return call(
      provider.userId,
    );
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'vitalHistoryProvider';
}

/// See also [vitalHistory].
class VitalHistoryProvider
    extends AutoDisposeStreamProvider<List<VitalLogEntity>> {
  /// See also [vitalHistory].
  VitalHistoryProvider(
    int userId,
  ) : this._internal(
          (ref) => vitalHistory(
            ref as VitalHistoryRef,
            userId,
          ),
          from: vitalHistoryProvider,
          name: r'vitalHistoryProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$vitalHistoryHash,
          dependencies: VitalHistoryFamily._dependencies,
          allTransitiveDependencies:
              VitalHistoryFamily._allTransitiveDependencies,
          userId: userId,
        );

  VitalHistoryProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.userId,
  }) : super.internal();

  final int userId;

  @override
  Override overrideWith(
    Stream<List<VitalLogEntity>> Function(VitalHistoryRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: VitalHistoryProvider._internal(
        (ref) => create(ref as VitalHistoryRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        userId: userId,
      ),
    );
  }

  @override
  AutoDisposeStreamProviderElement<List<VitalLogEntity>> createElement() {
    return _VitalHistoryProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is VitalHistoryProvider && other.userId == userId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, userId.hashCode);

    return _SystemHash.finish(hash);
  }
}

mixin VitalHistoryRef on AutoDisposeStreamProviderRef<List<VitalLogEntity>> {
  /// The parameter `userId` of this provider.
  int get userId;
}

class _VitalHistoryProviderElement
    extends AutoDisposeStreamProviderElement<List<VitalLogEntity>>
    with VitalHistoryRef {
  _VitalHistoryProviderElement(super.provider);

  @override
  int get userId => (origin as VitalHistoryProvider).userId;
}

String _$selectedUserLiveVitalsHash() =>
    r'ca5a312c9b9bcaa7114ade6cde62f6d117b42550';

/// See also [selectedUserLiveVitals].
@ProviderFor(selectedUserLiveVitals)
final selectedUserLiveVitalsProvider =
    AutoDisposeStreamProvider<SerialPacket>.internal(
  selectedUserLiveVitals,
  name: r'selectedUserLiveVitalsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$selectedUserLiveVitalsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef SelectedUserLiveVitalsRef = AutoDisposeStreamProviderRef<SerialPacket>;
String _$liveVitalStreamHash() => r'7e44d0b0eb71455cba17b2a15799983f4b600e4a';

/// See also [liveVitalStream].
@ProviderFor(liveVitalStream)
const liveVitalStreamProvider = LiveVitalStreamFamily();

/// See also [liveVitalStream].
class LiveVitalStreamFamily extends Family<AsyncValue<SerialPacket>> {
  /// See also [liveVitalStream].
  const LiveVitalStreamFamily();

  /// See also [liveVitalStream].
  LiveVitalStreamProvider call(
    int userId,
  ) {
    return LiveVitalStreamProvider(
      userId,
    );
  }

  @override
  LiveVitalStreamProvider getProviderOverride(
    covariant LiveVitalStreamProvider provider,
  ) {
    return call(
      provider.userId,
    );
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'liveVitalStreamProvider';
}

/// See also [liveVitalStream].
class LiveVitalStreamProvider extends AutoDisposeStreamProvider<SerialPacket> {
  /// See also [liveVitalStream].
  LiveVitalStreamProvider(
    int userId,
  ) : this._internal(
          (ref) => liveVitalStream(
            ref as LiveVitalStreamRef,
            userId,
          ),
          from: liveVitalStreamProvider,
          name: r'liveVitalStreamProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$liveVitalStreamHash,
          dependencies: LiveVitalStreamFamily._dependencies,
          allTransitiveDependencies:
              LiveVitalStreamFamily._allTransitiveDependencies,
          userId: userId,
        );

  LiveVitalStreamProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.userId,
  }) : super.internal();

  final int userId;

  @override
  Override overrideWith(
    Stream<SerialPacket> Function(LiveVitalStreamRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: LiveVitalStreamProvider._internal(
        (ref) => create(ref as LiveVitalStreamRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        userId: userId,
      ),
    );
  }

  @override
  AutoDisposeStreamProviderElement<SerialPacket> createElement() {
    return _LiveVitalStreamProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is LiveVitalStreamProvider && other.userId == userId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, userId.hashCode);

    return _SystemHash.finish(hash);
  }
}

mixin LiveVitalStreamRef on AutoDisposeStreamProviderRef<SerialPacket> {
  /// The parameter `userId` of this provider.
  int get userId;
}

class _LiveVitalStreamProviderElement
    extends AutoDisposeStreamProviderElement<SerialPacket>
    with LiveVitalStreamRef {
  _LiveVitalStreamProviderElement(super.provider);

  @override
  int get userId => (origin as LiveVitalStreamProvider).userId;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
