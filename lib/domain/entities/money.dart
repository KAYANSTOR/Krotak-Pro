final class Money {
  const Money({required this.minorUnits, required this.currencyCode});

  final int minorUnits;
  final String currencyCode;

  Money copyWith({int? minorUnits, String? currencyCode}) {
    return Money(
      minorUnits: minorUnits ?? this.minorUnits,
      currencyCode: currencyCode ?? this.currencyCode,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is Money &&
        other.minorUnits == minorUnits &&
        other.currencyCode == currencyCode;
  }

  @override
  int get hashCode => Object.hash(minorUnits, currencyCode);
}
