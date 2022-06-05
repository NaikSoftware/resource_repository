import 'package:flutter_test/flutter_test.dart';
import 'package:resource_repository/src/memory_cache_storage.dart';
import 'package:resource_repository/src/stream_repository.dart';

void main() {
  test('watch triggered', () async {
    final repo = StreamRepository<String, int>.local(
        storage: MemoryCacheStorage('storage'));
    expect(
        repo.watch(),
        emitsInOrder([
          [],
          [1],
          [1, 2],
          [2],
          [3],
        ]));
    await repo.putValue('key1', 1);
    await repo.putValue('key2', 2);
    await repo.clear('key1');
    await repo.updateValue('key2', (_) => 3);
  });
}
