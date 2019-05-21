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
[v2.1.0](
https://pub.dartlang.org/packages/synchronized/versions/2.1.0) to properly
synchronize inner blocks on reentrant locks.
- improved [example](
https://pub.dartlang.org/packages/flutter_persistent_queue#-example-tab-)

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
