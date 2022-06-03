## Resource Repository

[![pub package](https://img.shields.io/pub/v/resource_repository.svg)](https://pub.dev/packages/resource_repository)

Implementation of a resource/repository pattern for data management in Flutter apps.

## Getting started

1. Add dependency `flutter pub add resource_repository`
2. Package uses `SimpleMemoryCacheStorage` by default. You can add others:
    1. Hive [resource_repository_hive](https://pub.dev/packages/resource_repository_hive). Recommended for small data.
    2. ObjectBox [resource_repository_objectbox](https://pub.dev/packages/resource_repository_objectbox). More efficient on big datasets.

## Usage
The repository can be "remote" or "local". Local should be used to manage data locally,
for example instead of shared_preferences when you need more than just a small key/value store.
The remote should provide a `FetchData` callback to load data from an external place, e.g. REST API call.
```dart
final localRepository = StreamRepository.local({
    CacheStorage<K, V>? storage, // pass any of the implementations of CacheStorage
  });
final remoteRepository = StreamRepository.remote({
   required FetchData<K, V> fetch,
   CacheStorage<K, V>? storage, // SimpleMemoryCacheStorage will be used if null
   Duration? cacheDuration,     // Pass duration value or duration resolver for complex logic.
   CacheDurationResolver<K, V>? cacheDurationResolver,
});
```
And then you can subscribe to the resource, watch all resources or use other functionality of repository.
```dart
final repository = StreamRepository<String, FooBar>.remote(
  fetch: (key, arguments) => apiCall(fooBarId: key),
  cacheDuration: const Duration(minutes: 30),
  storage: SimpleMemoryCacheStorage('foobar_storage_key'),
);

repository.stream('1234').listen((fooBar) {
  // work with resource
});

// Do something

repository.invalidate('1234'); // reload
```

## Additional information

If you've created a new implementation of CacheStorage, please let me know on the project's github page. I'll add it to the readme.

### Authors

- [drstranges](https://github.com/drstranges)
- [NaikSoftware](https://github.com/NaikSoftware)
- [MagTuxGit](https://github.com/MagTuxGit)
