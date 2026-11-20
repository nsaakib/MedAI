/// All purchase calculations use integer paisa and whole supplier packs.
int packsFor(int units, int unitsPerPack) {
  if (units < 1 || unitsPerPack < 1) throw ArgumentError('Invalid quantity');
  return (units + unitsPerPack - 1) ~/ unitsPerPack;
}

int packTotal(int units, int packSize, int packPrice) {
  if (packPrice < 1) throw ArgumentError('Unknown pack price');
  return packsFor(units, packSize) * packPrice;
}

String quantityFormKey(String value) {
  final key = value.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
  return {
        'tab': 'tablet',
        'tablets': 'tablet',
        'cap': 'capsule',
        'capsules': 'capsule',
        'syp': 'syrup',
        'inj': 'injection',
      }[key] ??
      key;
}

String strengthKey(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
