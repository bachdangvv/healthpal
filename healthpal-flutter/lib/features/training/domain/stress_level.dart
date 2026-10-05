/// Legacy training-only stress enum. Fatigue domain must not depend on this.
enum StressLevel {
  low(1),
  medium(2),
  high(3);

  const StressLevel(this.rank);
  final int rank;
}
