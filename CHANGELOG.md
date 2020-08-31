## [6.1.1] - 2020-08-31
- minor refactor

## [6.0.4] - 2020-04-29
- dependency updates

## [6.0.3] - 2020-02-20
- improve config overriding

## [6.0.2] - 2020-02-20
- fix: allow config overrides to match previous v5 behavior

## [6.0.1] - 2020-02-20
- major refactor to improve maintainability

## [5.1.1] - 2019-12-26
- updated dependencies

## [5.1.0] - 2019-10-24
- [localstorage](https://pub.dev/packages/localstorage) dependency bumped to v3
- integration tests reviewed

## [5.0.1] - 2019-10-16
- fixed a caching bug related to the OnFlush callback

## [5.0.0] - 2019-10-14
- breaking change: constructor now always overrides previous queue settings, even on cache hits
- deprecated parameters: filePath, growable, noCache, noPersist
- updated iOS build settings

## [4.0.0] - 2019-10-11
- breaking change: `<dynamic>` json encodable data beyond `Map<String, dynamic>` now accepted

## [3.0.0+1] - 2019-09-17
- minor maintenance

## [3.0.0] - 2019-05-22
- breaking change: `OnFlush` handlers must now return a `boolean` "ack" instead
  of `void`

## [2.0.1+2] - 2019-05-21
- minor style fix

## [2.0.1+1] - 2019-05-21
- rebuilt docs

## [2.0.1] - 2019-05-21
- alias feature added
- cleaner example and tests
- updated `localstorage` to v2.0.0
- breaking change: `length()` method now returns `Future<int>` to avoid
  ambiguity and edgy race conditions

## [1.0.2] - 2019-05-09
- updated documentation

## [1.0.1] - 2019-05-09
- minor source code whitespace fix

## [1.0.0] - 2019-05-09
- new buffered implementation to enforce sequential behavior
- integration tests added, including throughput performance benchmarking

## [0.1.4] - 2019-02-27
- bump [synchronized](https://pub.dartlang.org/packages/synchronized) to
  [v2.1.0](https://pub.dartlang.org/packages/synchronized/versions/2.1.0) to properly
  synchronize inner blocks on reentrant locks.
- improved [example](https://pub.dartlang.org/packages/flutter_persistent_queue#-example-tab-)

## [0.1.3] - 2019-02-27
- silent flush/push error handling if user does not provide handlers
- hard `maxLength` parameter added to enforce an absolute maximum queue length

## [0.1.2] - 2019-02-26
- fix error message and add stack trace to error handling

## [0.1.1] - 2019-02-25
- user-specified error handling behavior while flushing

## [0.1.0] - 2019-02-21
- minor source code readability improvements
- no-reload feature added to `setup` method
- improved example using `FutureBuilder`
- no additional example dependencies

## [0.0.1] - 2019-02-20
- Initial release
