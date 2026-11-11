double roundToNearestRupee(double amount) {
  final double truncated = amount.truncateToDouble();
  final double fractional = amount - truncated;

  if (fractional >= 0.5) {
    return truncated + 1;
  }
  if (fractional <= -0.5) {
    return truncated - 1;
  }
  return truncated;
}

class RoundOffResult {
  final double roundedTotal;
  final double numericRoundOff;
  final String formattedRoundOff;

  const RoundOffResult({
    required this.roundedTotal,
    required this.numericRoundOff,
    required this.formattedRoundOff,
  });
}

RoundOffResult calculateRoundOff(double amount) {
  final double rounded = roundToNearestRupee(amount);
  final double difference = rounded - amount;
  final double numeric = double.parse(difference.toStringAsFixed(2));
  final bool isPositive = numeric > 0;
  final bool isNegative = numeric < 0;
  final String formatted;
  if (isPositive) {
    formatted = '+${numeric.toStringAsFixed(2)}';
  } else if (isNegative) {
    formatted = '-${numeric.abs().toStringAsFixed(2)}';
  } else {
    formatted = '0.00';
  }

  return RoundOffResult(
    roundedTotal: double.parse((amount + numeric).toStringAsFixed(2)),
    numericRoundOff: numeric,
    formattedRoundOff: formatted,
  );
}
