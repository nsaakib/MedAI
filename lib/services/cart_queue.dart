// Row-level review is a completed attempt. Only a global interruption
// (cancel, untrusted navigation, or sign-in not completed) returns false.
Future<bool> processCartQueue(
  int count,
  bool Function() active,
  Future<bool> Function(int index) attempt,
) async {
  for (var i = 0; i < count; i++) {
    if (!active() || !await attempt(i)) return false;
  }
  return active();
}
