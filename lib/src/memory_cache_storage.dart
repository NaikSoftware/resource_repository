/*
 * Copyright (c) Resource Repository
 * 2020-2022 drstranges, NaikSoftware, MagTuxGit
 */

import 'package:resource_repository_storage/resource_repository_storage.dart';
import 'package:rxdart/rxdart.dart';
import 'package:synchronized/synchronized.dart';

/// A simple implementation of [CacheStorage]. Used by default.
/// It just keeps the data in memory.
class MemoryCacheStorage<K, V> implements CacheStorage<K, V> {
  static final _lock = Lock();
  static final Map<String, BehaviorSubject<Map<dynamic, CacheEntry<dynamic>>>>
      _boxes = {};

  final String _boxKey;

  /// Create instance. Takes a unique key for storing data in separate boxes for every repository.
  MemoryCacheStorage(this._boxKey);

  @override
  Future<void> ensureInitialized() => Future.value();

  /// Clears all data stored by all repositories in [MemoryCacheStorage].
  static Future<void> clearAll() async {
    _boxes.clear();
  }

  Future<BehaviorSubject<Map<K, CacheEntry<V>>>> _ensureBox() =>
      _lock.synchronized(() async {
        var box = _boxes[_boxKey] as BehaviorSubject<Map<K, CacheEntry<V>>>?;
        if (box == null) {
          box = BehaviorSubject.seeded(<K, CacheEntry<V>>{});
          _boxes[_boxKey] = box;
        }
        return box;
      });

  @override
  Future<void> clear() => _ensureBox().then((box) => box.value = {});

  @override
  Future<CacheEntry<V>?> get(K cacheKey) async {
    return (await _ensureBox()).value[cacheKey];
  }

  @override
  Future<void> put(K cacheKey, V data, {int? storeTime}) async {
    final box = await _ensureBox();
    box.value = {
      ...box.value,
      cacheKey: CacheEntry(
        data,
        storeTime: storeTime ?? DateTime.now().millisecondsSinceEpoch,
      )
    };
  }

  @override
  Future<void> delete(K cacheKey) async {
    final box = await _ensureBox();
    final newValue = {...box.value}..remove(cacheKey);
    box.value = newValue;
  }

  @override
  Stream<List<V>> watch() => _ensureBox()
      .asStream()
      .switchMap((box) => box)
      .map((map) => map.values.map((e) => e.data).toList());

  @override
  Future<List<V>> getAll() =>
      _ensureBox().then((box) => box.value.values.map((e) => e.data).toList());

  @override
  String toString() => 'MemoryCacheStorage($_boxKey)';
}
