import 'dart:math';

abstract interface class IdGenerator {
  String next(String prefix);
}

final class SequentialIdGenerator implements IdGenerator {
  SequentialIdGenerator({int start = 1}) : _next = start;

  int _next;

  @override
  String next(String prefix) => '$prefix-${_next++}';
}

final class RandomIdGenerator implements IdGenerator {
  RandomIdGenerator([Random? random]) : _random = random ?? Random.secure();

  final Random _random;

  @override
  String next(String prefix) {
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final noise = _random.nextInt(1 << 32).toRadixString(16);
    return '$prefix-$stamp-$noise';
  }
}
