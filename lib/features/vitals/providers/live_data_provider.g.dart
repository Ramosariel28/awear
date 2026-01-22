// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'live_data_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$selectedUserLiveVitalsHash() =>
    r'2dd6432b2427cf0e93fb4ae0bd5b171e1def6a74';

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
String _$vitalHistoryHash() => r'f51d9ad392876960f49f1f8467ae18e278acab46';

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
  VitalHistoryProvider call(int userId) {
    return VitalHistoryProvider(userId);
  }

  @override
  VitalHistoryProvider getProviderOverride(
    covariant VitalHistoryProvider provider,
  ) {
    return call(provider.userId);
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
  VitalHistoryProvider(int userId)
    : this._internal(
        (ref) => vitalHistory(ref as VitalHistoryRef, userId),
        from: vitalHistoryProvider,
        name: r'vitalHistoryProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
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

String _$clearUserHistoryHash() => r'63506b7bd26c1c53a3cf19af7426e757babd7259';

/// See also [clearUserHistory].
@ProviderFor(clearUserHistory)
const clearUserHistoryProvider = ClearUserHistoryFamily();

/// See also [clearUserHistory].
class ClearUserHistoryFamily extends Family<AsyncValue<void>> {
  /// See also [clearUserHistory].
  const ClearUserHistoryFamily();

  /// See also [clearUserHistory].
  ClearUserHistoryProvider call(int userId) {
    return ClearUserHistoryProvider(userId);
  }

  @override
  ClearUserHistoryProvider getProviderOverride(
    covariant ClearUserHistoryProvider provider,
  ) {
    return call(provider.userId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'clearUserHistoryProvider';
}

/// See also [clearUserHistory].
class ClearUserHistoryProvider extends AutoDisposeFutureProvider<void> {
  /// See also [clearUserHistory].
  ClearUserHistoryProvider(int userId)
    : this._internal(
        (ref) => clearUserHistory(ref as ClearUserHistoryRef, userId),
        from: clearUserHistoryProvider,
        name: r'clearUserHistoryProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$clearUserHistoryHash,
        dependencies: ClearUserHistoryFamily._dependencies,
        allTransitiveDependencies:
            ClearUserHistoryFamily._allTransitiveDependencies,
        userId: userId,
      );

  ClearUserHistoryProvider._internal(
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
    FutureOr<void> Function(ClearUserHistoryRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: ClearUserHistoryProvider._internal(
        (ref) => create(ref as ClearUserHistoryRef),
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
  AutoDisposeFutureProviderElement<void> createElement() {
    return _ClearUserHistoryProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ClearUserHistoryProvider && other.userId == userId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, userId.hashCode);

    return _SystemHash.finish(hash);
  }
}

mixin ClearUserHistoryRef on AutoDisposeFutureProviderRef<void> {
  /// The parameter `userId` of this provider.
  int get userId;
}

class _ClearUserHistoryProviderElement
    extends AutoDisposeFutureProviderElement<void>
    with ClearUserHistoryRef {
  _ClearUserHistoryProviderElement(super.provider);

  @override
  int get userId => (origin as ClearUserHistoryProvider).userId;
}

String _$liveVitalStreamHash() => r'69127d8671f7830ef2eb4bf02abb26e837964a7a';

abstract class _$LiveVitalStream
    extends BuildlessAutoDisposeStreamNotifier<SerialPacket> {
  late final int userId;

  Stream<SerialPacket> build(int userId);
}

/// See also [LiveVitalStream].
@ProviderFor(LiveVitalStream)
const liveVitalStreamProvider = LiveVitalStreamFamily();

/// See also [LiveVitalStream].
class LiveVitalStreamFamily extends Family<AsyncValue<SerialPacket>> {
  /// See also [LiveVitalStream].
  const LiveVitalStreamFamily();

  /// See also [LiveVitalStream].
  LiveVitalStreamProvider call(int userId) {
    return LiveVitalStreamProvider(userId);
  }

  @override
  LiveVitalStreamProvider getProviderOverride(
    covariant LiveVitalStreamProvider provider,
  ) {
    return call(provider.userId);
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

/// See also [LiveVitalStream].
class LiveVitalStreamProvider
    extends
        AutoDisposeStreamNotifierProviderImpl<LiveVitalStream, SerialPacket> {
  /// See also [LiveVitalStream].
  LiveVitalStreamProvider(int userId)
    : this._internal(
        () => LiveVitalStream()..userId = userId,
        from: liveVitalStreamProvider,
        name: r'liveVitalStreamProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
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
  Stream<SerialPacket> runNotifierBuild(covariant LiveVitalStream notifier) {
    return notifier.build(userId);
  }

  @override
  Override overrideWith(LiveVitalStream Function() create) {
    return ProviderOverride(
      origin: this,
      override: LiveVitalStreamProvider._internal(
        () => create()..userId = userId,
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
  AutoDisposeStreamNotifierProviderElement<LiveVitalStream, SerialPacket>
  createElement() {
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

mixin LiveVitalStreamRef on AutoDisposeStreamNotifierProviderRef<SerialPacket> {
  /// The parameter `userId` of this provider.
  int get userId;
}

class _LiveVitalStreamProviderElement
    extends
        AutoDisposeStreamNotifierProviderElement<LiveVitalStream, SerialPacket>
    with LiveVitalStreamRef {
  _LiveVitalStreamProviderElement(super.provider);

  @override
  int get userId => (origin as LiveVitalStreamProvider).userId;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
