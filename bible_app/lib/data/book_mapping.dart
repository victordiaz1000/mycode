/// Mapping between the BYM file order (01..66, Hebrew-canon order) and the
/// standard getbible book numbers (1=Genesis .. 66=Revelation, standard order).
///
/// BYM indexes are 1-based and match the `0X-File.json` names in
/// `assets/bible/bym/`. Standard numbers are what the getbible API
/// (`api.getbible.net/v2/<translation>/<book_nr>/<chapter>.json`) expects.
library;

const Map<int, int> _bymToStandard = {
  1: 1, // Genèse
  2: 2, // Exode
  3: 3, // Lévitique
  4: 4, // Nombres
  5: 5, // Deutéronome
  6: 6, // Josué
  7: 7, // Juges
  8: 9, // 1 Samuel
  9: 10, // 2 Samuel
  10: 11, // 1 Rois
  11: 12, // 2 Rois
  12: 23, // Ésaïe
  13: 24, // Jérémie
  14: 26, // Ézéchiel
  15: 28, // Osée
  16: 29, // Joël
  17: 30, // Amos
  18: 31, // Abdias
  19: 32, // Jonas
  20: 33, // Michée
  21: 34, // Nahum
  22: 35, // Habakuk
  23: 36, // Sophonie
  24: 37, // Aggée
  25: 38, // Zacharie
  26: 39, // Malachie
  27: 19, // Psaumes
  28: 20, // Proverbes
  29: 18, // Job
  30: 22, // Cantiques
  31: 8, // Ruth
  32: 25, // Lamentations
  33: 21, // Ecclésiaste
  34: 17, // Esther
  35: 27, // Daniel
  36: 15, // Esdras
  37: 16, // Néhémie
  38: 13, // 1 Chroniques
  39: 14, // 2 Chroniques
  40: 40, // Matthieu
  41: 41, // Marc
  42: 42, // Luc
  43: 43, // Jean
  44: 44, // Actes
  45: 59, // Jacques
  46: 48, // Galates
  47: 52, // 1 Thessaloniciens
  48: 53, // 2 Thessaloniciens
  49: 46, // 1 Corinthiens
  50: 47, // 2 Corinthiens
  51: 45, // Romains
  52: 49, // Éphésiens
  53: 50, // Philippiens
  54: 51, // Colossiens
  55: 57, // Philémon
  56: 54, // 1 Timothée
  57: 56, // Tite
  58: 60, // 1 Pierre
  59: 61, // 2 Pierre
  60: 55, // 2 Timothée
  61: 65, // Jude
  62: 58, // Hébreux
  63: 62, // 1 Jean
  64: 63, // 2 Jean
  65: 64, // 3 Jean
  66: 66, // Apocalypse
};

/// Maps a BYM index (1..66) to the standard getbible book number.
int bymToStandard(int bymIndex) => _bymToStandard[bymIndex] ?? bymIndex;

/// Maps a getbible standard book number (1..66) back to the BYM index.
int standardToBym(int standard) {
  for (final entry in _bymToStandard.entries) {
    if (entry.value == standard) return entry.key;
  }
  return standard;
}
