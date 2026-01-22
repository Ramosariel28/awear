// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$isarHash() => r'7d236a4abeef51e8153981657eb4f3a2e3e3cff5';

/// 1. DATABASE PROVIDER
/// This opens the Isar database asynchronously.
///
/// Copied from [isar].
@ProviderFor(isar)
final isarProvider = FutureProvider<Isar>.internal(
  isar,
  name: r'isarProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$isarHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef IsarRef = FutureProviderRef<Isar>;
String _$serialServiceHash() => r'837166a7369f34e949a0415019d56afacf85f6c6';

/// 2. SERIAL SERVICE PROVIDER
/// This gives the UI the correct serial implementation based on the OS.
///
/// Copied from [serialService].
@ProviderFor(serialService)
final serialServiceProvider = Provider<SerialServiceContract>.internal(
  serialService,
  name: r'serialServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$serialServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef SerialServiceRef = ProviderRef<SerialServiceContract>;
String _$syncServiceHash() => r'693d115d028caa441308df23cd1076bbbce29b04';

/// 3. SYNC SERVICE PROVIDER
/// This lets us sync to Firebase.
///
/// Copied from [syncService].
@ProviderFor(syncService)
final syncServiceProvider = Provider<SyncService>.internal(
  syncService,
  name: r'syncServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$syncServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef SyncServiceRef = ProviderRef<SyncService>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
