/*
 * Copyright (c) Resource Repository
 * 2020-2022 drstranges, NaikSoftware, MagTuxGit
 */

import 'package:resource_repository_storage/resource_repository_storage.dart';
import 'package:synchronized/synchronized.dart';

/// A simple implementation of [CacheStorage]. Used by default.
/// It just keeps the data in memory.
class SimpleMemoryCacheStorage<K, V> implements CacheStorage<K, V> {
  static final _lock = Lock();
  static final Map<String, Map> _boxes = {};

  final String _boxKey;

  /// Create instance. Takes a unique key for storing data in separate boxes for every repository.
  SimpleMemoryCacheStorage(this._boxKey);

  @override
  Future<void> ensureInitialized() => Future.value();

  /// Clears all data stored by all repositories in [SimpleMemoryCacheStorage].
  static Future<void> clearAll() async {
    _boxes.clear();
  }

  Future<Map<K, CacheEntry<V>>> _ensureBox() => _lock.synchronized(() async {
        Map? box = _boxes[_boxKey];
        if (box == null) {
          box = <K, CacheEntry<V>>{};
          _boxes[_boxKey] = box;
        }
        return box as Map<K, CacheEntry<V>>;
      });

  @override
  Future<void> clear() => _ensureBox().then((box) => box.clear());

  @override
  Future<CacheEntry<V>?> get(K cacheKey) async {
    return (await _ensureBox())[cacheKey];
  }

  @override
  Future<void> put(K cacheKey, V data, {int? storeTime}) async {
    final box = await _ensureBox();
    box[cacheKey] = CacheEntry(
      data,
      storeTime: storeTime ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Future<void> delete(K cacheKey) async {
    (await _ensureBox()).remove(cacheKey);
  }

  /// Not implemented yet
  @override
  Stream<List<V>> watch() =>
      throw UnsupportedError('Not supported yet for MemoryCacheStorage!');

  @override
  Future<List<V>> getAll() =>
      _ensureBox().then((box) => box.values.map((e) => e.data).toList());

  @override
  String toString() => 'MemoryCacheStorage($_boxKey)';
}
