// Check quickly during the first few seconds for hydration and acknowledgement.
// Long-running pages retain the usual slower polling and unchanged deadline.
Duration cartProbeDelay(Duration elapsed, {bool justClicked = false}) {
  if (justClicked) return const Duration(milliseconds: 95);
  if (elapsed < const Duration(seconds: 3)) {
    return const Duration(milliseconds: 135);
  }
  if (elapsed < const Duration(seconds: 8)) {
    return const Duration(milliseconds: 250);
  }
  return const Duration(milliseconds: 500);
}
