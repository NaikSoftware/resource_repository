/*
 * Copyright (c) 2022 Score Counter
 * 2020-2021 NaikSoftware, drstranges, MagTuxGit
 */

import 'dart:async';
import 'dart:developer';

import 'package:resource_repository_storage/resource_repository_storage.dart';
import 'package:rxdart/rxdart.dart';
import 'package:synchronized/synchronized.dart';

import 'resource.dart';

/// Resource used for managing the data. Allows load, invalidate, clear local
/// data or use with delegated [_fetch] callback.
class StreamResource<K, V> {
  final BehaviorSubject<Resource<V>> _subject = BehaviorSubject<Resource<V>>();
  final CacheStorage<K, V> _storage;
  final Future<V> Function(K key, ResourceFetchArguments? arguments)? _fetch;
  final K _resourceKey;
  final CacheDurationResolver<K, V> _cacheDurationResolver;

  final _lock = Lock();
  bool _isLoading = false;
  bool _shouldReload = false;

  /// Creates an instance. Usually you don't need to create directly.
  /// It is used inside the repositories.
  StreamResource(
    this._fetch,
    this._resourceKey,
    this._cacheDurationResolver,
    this._storage,
  );

  /// Trigger resource loading from cache or with [_fetch].
  /// [forceReload] reload even if cache is valid.
  /// [allowEmptyLoading] put empty loading to prevent previous SUCCESS to return.
  /// [doOnStore] callback to modify data before putting it in the storage.
  /// [fetchArguments] additional arguments passed to [_fetch] if provided.
  Stream<Resource<V>> load({
    bool forceReload = false,
    void Function(V)? doOnStore,
    bool allowEmptyLoading = false,
    final ResourceFetchArguments? fetchArguments,
  }) {
    if (!_isLoading) {
      _isLoading = true;
      _lock.synchronized(() async {
        _shouldReload = false;
        // try always starting with loading value
        if (allowEmptyLoading || _subject.hasValue) {
          // prevent previous SUCCESS to return
          _subject.add(Resource.loading(_subject.valueOrNull?.data));
        }
        await _loadProcess(forceReload, doOnStore, fetchArguments);
      }).then((_) {
        _isLoading = false;
        if (_shouldReload) {
          load(
            forceReload: forceReload,
            doOnStore: doOnStore,
            allowEmptyLoading: allowEmptyLoading,
          );
        }
      });
    } else if (forceReload) {
      // don't need to call load many times
      // perform another load only once
      _shouldReload = true;
    }
    return _subject;
  }

  Future<void> _loadProcess(
    bool forceReload,
    void Function(V)? doOnStore,
    ResourceFetchArguments? fetchArguments,
  ) async {
    // fetch value from DB
    final cached = await _storage.get(_resourceKey);
    if (cached != null) {
      final cacheDuration =
          _cacheDurationResolver(_resourceKey, cached.data).inMilliseconds;

      if (cached.storeTime <
          DateTime.now().millisecondsSinceEpoch - cacheDuration) {
        forceReload = true;
      }
    }

    if (cached != null || _fetch == null) {
      if (forceReload && _fetch != null) {
        final resource = Resource.loading(cached?.data);
        if (_subject.valueOrNull != resource) {
          _subject.add(resource);
        }
      } else {
        final resource = Resource.success(cached?.data);
        if (_subject.valueOrNull != resource) {
          _subject.add(resource);
        }
        return;
      }
    }

    // no need to perform another load while fetch not called yet
    _shouldReload = false;

    // fetch value from network
    return _subject.addStream(_fetch!(_resourceKey, fetchArguments)
        .asStream()
        .asyncMap((data) async {
          if (doOnStore != null) {
            doOnStore(data);
          }
          await _storage.put(_resourceKey, data);
          return data;
        })
        .map((data) => Resource.success(data))
        .doOnError((error, trace) => log(
            'Error loading resource by id $_resourceKey with storage $_storage',
            error: error,
            stackTrace: trace))
        .onErrorReturnWith((error, trace) => Resource.error(
            'Resource $_resourceKey loading error',
            error: error,
            data: cached?.data)));
  }

  /// Update value directly in storage.
  Future<void> updateValue(V? Function(V? value) changeValue,
      {bool notifyOnNull = false}) async {
    _lock.synchronized(() async {
      final cached = await _storage.get(_resourceKey);
      final newValue = changeValue.call(cached?.data);

      if (newValue != null) {
        await _storage.put(
          _resourceKey,
          newValue,
          storeTime: cached?.storeTime ?? 0,
        );

        _subject.add(Resource.success(newValue));
      } else if (cached != null) {
        await _storage.delete(_resourceKey);
        if (notifyOnNull) _subject.add(Resource.success(null));
      }
    });
  }

  /// Put or replace value by [_resourceKey] in the storage.
  Future<void> putValue(V value) async {
    assert(value != null);

    _lock.synchronized(() async {
      await _storage.put(_resourceKey, value);
      _subject.add(Resource.success(value));
    });
  }

  Future<void> _clearCache() async {
    await _storage.ensureInitialized();
    await _storage.delete(_resourceKey);
  }

  Future<void> _resetStoreTime() async {
    _lock.synchronized(() async {
      var cached = await _storage.get(_resourceKey);
      if (cached != null) {
        await _storage.put(_resourceKey, cached.data, storeTime: 0);
      } else {
        await _storage.delete(_resourceKey);
      }
    });
  }

  /// Invalidates the cached value and force a resource reload.
  Future<void> invalidate() async {
    // don't clear cache for offline usage
    //await _clearCache();
    await _resetStoreTime();
    await load(forceReload: true).where((event) => event.isNotLoading).first;
  }

  /// Deletes the cached value and closes the resource. After that, it cannot be used.
  Future<void> close() async {
    await _clearCache();
    _subject.close(); // TODO: Maybe leave not closed? Need tests
  }
}

/// Optional arguments passes into [StreamResource._fetch].
// TODO: make it more universal/abstract
class ResourceFetchArguments {
  /// Typically limit param in the rest queries.
  final int? limit;

  /// Can be used as token for authorize request.
  final String? permissionToken;

  /// Any object that can be accessed in [StreamResource._fetch].
  final dynamic payload;

  const ResourceFetchArguments({
    this.limit,
    this.permissionToken,
    this.payload,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResourceFetchArguments &&
          runtimeType == other.runtimeType &&
          permissionToken == other.permissionToken;

  @override
  int get hashCode => permissionToken.hashCode;
}

/// Should return the duration of the cache.
typedef CacheDurationResolver<K, V> = Duration Function(K key, V value);
