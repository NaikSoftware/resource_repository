/*
 * Copyright (c) Resource Repository
 * 2020-2022 drstranges, NaikSoftware, MagTuxGit
 */

import 'dart:async';

import 'package:resource_repository_storage/resource_repository_storage.dart';
import 'package:rxdart/rxdart.dart';
import 'package:synchronized/synchronized.dart';
import 'package:uuid/uuid.dart';

import 'memory_cache_storage.dart';
import 'resource.dart';
import 'stream_resource.dart';

/// Fetch data from external service callback. Typically REST API call.
typedef FetchData<K, V> = Future<V> Function(
  K key,
  ResourceFetchArguments? arguments,
);

/// Repository for resource management.
class StreamRepository<K, V> {
  final Map<K, StreamResource<K, V>> _resources = {};
  final FetchData<K, V>? fetch;
  final CacheDurationResolver<K, V> cacheDurationResolver;
  final Map<K, bool> _firstLoad = {};
  final _lock = Lock();
  final CacheStorage<K, V> storage;

  StreamRepository._({
    this.fetch,
    required this.storage,
    Duration? cacheDuration,
    CacheDurationResolver<K, V>? cacheDurationResolver,
  }) : cacheDurationResolver =
            (cacheDurationResolver ?? (k, v) => cacheDuration ?? Duration.zero);

  /// Creates repository with providing [fetch] callback, typically used for REST API call.
  /// Caches data in the passed [CacheStorage]. The default is [MemoryCacheStorage].
  StreamRepository.remote({
    required FetchData<K, V> fetch,
    CacheStorage<K, V>? storage,
    Duration? cacheDuration,
    CacheDurationResolver<K, V>? cacheDurationResolver,
  }) : this._(
          fetch: fetch,
          storage: storage ?? MemoryCacheStorage<K, V>(const Uuid().v4()),
          cacheDuration: cacheDuration,
          cacheDurationResolver: cacheDurationResolver,
        );

  /// Creates repository for use as local data storage.
  /// Caches data in the passed [CacheStorage].
  StreamRepository.local({required CacheStorage<K, V> storage})
      : this._(
          storage: storage,
          cacheDuration: Duration.zero,
        );

  /// Creates a stream by [key]. It emits the cached data,
  /// then the [fetch] result if provided, and after that any changes to the resource
  /// due to reloading or invalidating the resource.
  Stream<Resource<V>> stream(
    K key, {
    bool? forceReload,
    void Function(V)? doOnStore,
    ResourceFetchArguments? fetchArguments,
    bool allowEmptyLoading = false,
  }) {
    final force = forceReload ?? _firstLoad[key] ?? true;
    _firstLoad[key] = false;
    return _ensureResource(key)
        .asStream()
        .switchMap((resource) => resource.load(
              forceReload: force,
              doOnStore: doOnStore,
              allowEmptyLoading: allowEmptyLoading,
              fetchArguments: fetchArguments,
            ));
  }

  /// Same as [stream], but waiting only for the first completed result.
  Future<Resource<V>> load(
    K key, {
    bool? forceReload,
    void Function(V)? doOnStore,
    ResourceFetchArguments? fetchArguments,
    bool allowEmptyLoading = false,
  }) =>
      stream(
        key,
        forceReload: forceReload,
        doOnStore: doOnStore,
        fetchArguments: fetchArguments,
        allowEmptyLoading: allowEmptyLoading,
      ).where((r) => r.isNotLoading).first;

  /// Invalidate resource by key and reload.
  Future<void> invalidate(K key) =>
      _resources[key]?.invalidate() ?? Future.value();

  /// Invalidate all resources and reload.
  Future<void> invalidateAll() =>
      Future.wait(_resources.values.map((r) => r.invalidate()));

  /// Update or replace value by [key] directly in the storage.
  Future<void> updateValue(K key, V? Function(V? value) changeValue,
          {bool notifyOnNull = false}) =>
      _ensureResource(key)
          .then((r) => r.updateValue(changeValue, notifyOnNull: notifyOnNull));

  /// Put value directly in the storage.
  Future<void> putValue(K key, V value) =>
      _ensureResource(key).then((r) => r.putValue(value));

  /// Stream of all stored entries that emits on any change of any resource.
  Stream<List<V>> watch() => storage.watch();

  /// Fetch all data from underlying storage.
  Future<List<V>> getAll() => storage.getAll();

  /// Clear, delete and dispose resource by [key] or all resources if a key not passed.
  Future<void> clear([K? key]) => _lock.synchronized(() async {
        if (key != null) {
          final resource = _resources[key];
          if (resource != null) {
            await resource.close();
            _resources.remove(key);
          } else {
            await storage.ensureInitialized();
            await storage.delete(key);
          }
        } else {
          _resources.clear();
          await storage.clear();
        }
      });

  Future<StreamResource<K, V>> _ensureResource(K key) =>
      _lock.synchronized(() async {
        var resource = _resources[key];
        if (resource == null) {
          resource = StreamResource<K, V>(
            fetch,
            key,
            cacheDurationResolver,
            storage,
          );
          _resources[key] = resource;
        }
        return resource;
      });
}
