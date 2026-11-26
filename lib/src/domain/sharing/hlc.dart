/// A hybrid logical clock (decision 0031): wall time in milliseconds, a
/// counter for changes in the same millisecond or behind a faster phone's
/// clock, and the member who made it, so every phone puts every change in
/// the same order.
///
/// Written as text that sorts in clock order: `000001763800000000-00000-m1`.
class Hlc implements Comparable<Hlc> {
  const Hlc(this.millis, this.counter, this.node);

  /// The earliest clock, before any change.
  static const zero = Hlc(0, 0, '');

  final int millis;
  final int counter;

  /// The member id that made the change. Ties on time and counter break
  /// on it, so two phones never disagree on which change is later.
  final String node;

  /// The clock for a new change made at [wallMillis] after [this].
  Hlc send(int wallMillis, String node) => wallMillis > millis
      ? Hlc(wallMillis, 0, node)
      : Hlc(millis, counter + 1, node);

  /// The clock after seeing [other], made at [wallMillis].
  Hlc receive(Hlc other, int wallMillis, String node) {
    final top = [
      millis,
      other.millis,
      wallMillis,
    ].reduce((a, b) => a > b ? a : b);
    if (top == millis && top == other.millis) {
      return Hlc(
        top,
        (counter > other.counter ? counter : other.counter) + 1,
        node,
      );
    }
    if (top == millis) return Hlc(top, counter + 1, node);
    if (top == other.millis) return Hlc(top, other.counter + 1, node);
    return Hlc(top, 0, node);
  }

  static Hlc parse(String text) {
    final first = text.indexOf('-');
    final second = text.indexOf('-', first + 1);
    if (first <= 0 || second <= first) {
      throw FormatException('Not a clock', text);
    }
    return Hlc(
      int.parse(text.substring(0, first)),
      int.parse(text.substring(first + 1, second)),
      text.substring(second + 1),
    );
  }

  @override
  String toString() =>
      '${millis.toString().padLeft(18, '0')}-'
      '${counter.toString().padLeft(5, '0')}-$node';

  @override
  int compareTo(Hlc other) {
    if (millis != other.millis) return millis.compareTo(other.millis);
    if (counter != other.counter) return counter.compareTo(other.counter);
    return node.compareTo(other.node);
  }

  bool operator >(Hlc other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is Hlc &&
      other.millis == millis &&
      other.counter == counter &&
      other.node == node;

  @override
  int get hashCode => Object.hash(millis, counter, node);
}
