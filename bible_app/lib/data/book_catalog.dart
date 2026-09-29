class BookEntry {
  final String name;
  final String abbreviation;
  final String file;

  /// The name the BYM itself gives this book, when it is not already the head of
  /// [name]. Only the books the BYM names in one word need it; the rest read
  /// `Bereshit (Genèse)` and the Hebrew is simply what precedes the parenthesis.
  ///
  /// Taken from `appCodebar/bym_md/*.md`, the markdown that *is* the BYM — never
  /// invented here. The twelve names the markdown does not carry are marked
  /// individually in the catalog.
  final String? bymName;

  const BookEntry(this.name, this.abbreviation, this.file, [this.bymName]);

  /// Compact French name used by the reading bar and the books sheet:
  /// the part between parentheses when the name is bilingual
  /// (`Bereshit (Genèse)` → `Genèse`), the whole name otherwise (`Amos`).
  String get shortName {
    final open = name.indexOf('(');
    if (open < 0) return name;
    final close = name.indexOf(')', open);
    if (close < 0) return name;
    return name.substring(open + 1, close).trim();
  }

  /// The book's own name in the BYM: `Bereshit`, `Shemot`, `Shir Hashirim`.
  ///
  /// This is the one thing on screen that says « you are reading the BYM » — a
  /// downloaded translation has no such name, which is the whole point. It is
  /// also the BYM's **text**, not a label we invented for it, so the reference a
  /// reader copies carries it.
  String get hebrewName {
    if (bymName != null) return bymName!;
    final open = name.indexOf('(');
    if (open < 0) return shortName;
    final head = name.substring(0, open).trim();
    return head.isEmpty ? shortName : head;
  }

  /// Compact French name used by the reading bar and the books sheet: the
  /// [shortName], except the books whose name would overflow the reference
  /// pill (« 1 Thessaloniciens » → « 1 Thess. »).
  String get barLabel => _compact(shortName);

  /// [hebrewName] shortened to fit the reference pill. The long French names are
  /// not the only ones that overflow: `Divrei Hayamim 1` is wider than
  /// « 1 Chroniques », and the pill has the same width either way.
  String get hebrewBarLabel => _compact(hebrewName);

  static const _long = <String, String>{
    // French
    '1 Thessaloniciens': '1 Thess.',
    '2 Thessaloniciens': '2 Thess.',
    '1 Corinthiens': '1 Cor.',
    '2 Corinthiens': '2 Cor.',
    '1 Chroniques': '1 Chr.',
    '2 Chroniques': '2 Chr.',
    // BYM
    '1 Tesalonika': '1 Thess.',
    '2 Tesalonika': '2 Thess.',
    '1 Korinthos': '1 Kor.',
    '2 Korinthos': '2 Kor.',
    'Divrei Hayamim 1': '1 Hay. d.',
    'Divrei Hayamim 2': '2 Hay. d.',
    'Meguila Esther': 'Meguila Est.',
    'Shir Hashirim': 'Shir Hash.',
  };

  static String _compact(String name) => _long[name] ?? name;
}

/// Whether [code] reads as the BYM itself.
///
/// **No code is not the BYM.** The surfaces that gather across versions — a
/// favourite, a note, a search result — have no single one, and defaulting them
/// to Hebrew would rename a Darby highlight to `Bereshit`, which is how a
/// French-speaking reader loses a highlight they can no longer find.
bool isBymVersion(String? code, String embeddedCode) => code == embeddedCode;

/// The book name to show, in the version being read.
///
/// French everywhere except the BYM, which keeps its own Hebrew names. Passing
/// [code] is what makes that choice; omit it and you get French, on purpose (see
/// [isBymVersion]).
String bookDisplayName(
  int bymIndex, {
  String? code,
  required String embeddedCode,
}) {
  final entry = catalogEntry(bymIndex);
  return isBymVersion(code, embeddedCode)
      ? entry.hebrewName
      : entry.shortName;
}

/// [bookDisplayName] shortened to fit a reference pill.
String bookDisplayLabel(
  int bymIndex, {
  String? code,
  required String embeddedCode,
}) {
  final entry = catalogEntry(bymIndex);
  return isBymVersion(code, embeddedCode)
      ? entry.hebrewBarLabel
      : entry.barLabel;
}

/// Static catalog of the 66 BYM books in file order (index = BYM number, 1-based).
const List<BookEntry> bookCatalog = [
  BookEntry('Bereshit (Genèse)', 'Ge.', '01-Genese.json'),
  BookEntry('Shemot (Exode)', 'Ex.', '02-Exode.json'),
  BookEntry('Vayiqra (Lévitique)', 'Lé.', '03-Levitique.json'),
  BookEntry('Bemidbar (Nombres)', 'No.', '04-Nombres.json'),
  BookEntry('Devarim (Deutéronome)', 'De.', '05-Deuteronome.json'),
  BookEntry('Yehoshoua (Josué)', 'Jos.', '06-Josue.json'),
  BookEntry('Shoftim (Juges)', 'Jg.', '07-Juges.json'),
  BookEntry('Shemouel 1 (1 Samuel)', '1 S.', '08-1Samuel.json'),
  BookEntry('Shemouel 2 (2 Samuel)', '2 S.', '09-2Samuel.json'),
  BookEntry('Melakim 1 (1 Rois)', '1 R.', '10-1Rois.json'),
  BookEntry('Melakim 2 (2 Rois)', '2 R.', '11-2Rois.json'),
  BookEntry('Yeshayahu (Ésaïe)', 'És.', '12-Esaie.json'),
  BookEntry('Yirmeyahu (Jérémie)', 'Jé.', '13-Jeremie.json'),
  BookEntry('Yehezqel (Ézéchiel)', 'Éz.', '14-Ezechiel.json'),
  BookEntry('Hoshea (Osée)', 'Os.', '15-Osee.json'),
  BookEntry('Yoël (Joël)', 'Jo.', '16-Joel.json'),
  BookEntry('Amos', 'Am.', '17-Amos.json', 'Amowc'),
  BookEntry('Ovadia (Abdias)', 'Ab.', '18-Abdias.json'),
  BookEntry('Yonah (Jonas)', 'Jon.', '19-Jonas.json'),
  BookEntry('Mikha (Michée)', 'Mi.', '20-Michee.json'),
  BookEntry('Nahum', 'Na.', '21-Nahum.json', 'Nahoum'),
  BookEntry('Habakuk', 'Ha.', '22-Habakuk.json', 'Habaqqouq'),
  BookEntry('Tsefania (Sophonie)', 'So.', '23-Sophonie.json'),
  BookEntry('Haggai (Aggée)', 'Ag.', '24-Aggee.json'),
  BookEntry('Zekharia (Zacharie)', 'Za.', '25-Zacharie.json'),
  BookEntry('Malakhi (Malachie)', 'Mal.', '26-Malachie.json'),
  BookEntry('Tehilim (Psaumes)', 'Ps.', '27-Psaumes.json'),
  BookEntry('Mishlei (Proverbes)', 'Pr.', '28-Proverbes.json'),
  BookEntry('Iyov (Job)', 'Job', '29-Job.json'),
  BookEntry('Shir Hashirim (Cantiques)', 'Ca.', '30-Cantiques.json'),
  BookEntry('Routh (Ruth)', 'Ru.', '31-Ruth.json'),
  BookEntry('Eikha (Lamentations)', 'La.', '32-Lamentations.json'),
  BookEntry('Qohelet (Ecclésiaste)', 'Ec.', '33-Ecclesiaste.json'),
  BookEntry('Esther', 'Est.', '34-Esther.json', 'Meguila Esther'),
  BookEntry('Daniel', 'Da.', '35-Daniel.json', "Daniye'l"),
  BookEntry('Ezra (Esdras)', 'Esd.', '36-Esdras.json'),
  BookEntry('Nehemia (Néhémie)', 'Né.', '37-Nehemie.json'),
  BookEntry('Divrei Hayamim 1 (1 Chroniques)', '1 Ch.', '38-1Chroniques.json'),
  BookEntry('Divrei Hayamim 2 (2 Chroniques)', '2 Ch.', '39-2Chroniques.json'),
  BookEntry('Matthieu', 'Mt.', '40-Matthieu.json', 'Mattithyah'),
  BookEntry('Marc', 'Mc.', '41-Marc.json', 'Markos'),
  BookEntry('Luc', 'Lc.', '42-Luc.json', 'Loukas'),
  BookEntry('Jean', 'Jn.', '43-Jean.json', 'Yohanan'),
  // ── The twelve names the BYM markdown does not carry ────────────────────
  // Its title line reads « Actes (Ac.) », « 1 Corinthiens (1 Co.) » — the French
  // name alone, no Hebrew. These are transliterated from the Septuagint's Greek
  // (Ivriyim from Hebrew for Hébreux), in the register the BYM itself uses for its
  // own Greek books — Markos, Loukas, Petros. **They are ours, not the text's:** if
  // bjc-source ever names them, take the name from there and delete this note.
  BookEntry('Actes', 'Ac.', '44-Actes.json', 'Diakonos'),
  BookEntry('Yaacov (Jacques)', 'Ja.', '45-Jacques.json'),
  BookEntry('Galates', 'Ga.', '46-Galates.json', 'Galatai'),
  BookEntry('1 Thessaloniciens', '1 Th.', '47-1Thessaloniciens.json', '1 Tesalonika'),
  BookEntry('2 Thessaloniciens', '2 Th.', '48-2Thessaloniciens.json', '2 Tesalonika'),
  BookEntry('1 Corinthiens', '1 Co.', '49-1Corinthiens.json', '1 Korinthos'),
  BookEntry('2 Corinthiens', '2 Co.', '50-2Corinthiens.json', '2 Korinthos'),
  BookEntry('Romains', 'Ro.', '51-Romains.json', 'Roma'),
  BookEntry('Éphésiens', 'Ép.', '52-Ephesiens.json', 'Efesos'),
  BookEntry('Philippiens', 'Ph.', '53-Philippiens.json', 'Filipoi'),
  BookEntry('Colossiens', 'Col.', '54-Colossiens.json', 'Kolossai'),
  BookEntry('Philémon', 'Phm.', '55-Philemon.json', 'Filimon'),
  BookEntry('1 Timothée', '1 Ti.', '56-1Timothee.json', '1 Timotheos'),
  BookEntry('Tite', 'Tit.', '57-Tite.json', 'Titos'),
  BookEntry('1 Pierre', '1 Pi.', '58-1Pierre.json', '1 Petros'),
  BookEntry('2 Pierre', '2 Pi.', '59-2Pierre.json', '2 Petros'),
  BookEntry('2 Timothée', '2 Ti.', '60-2Timothee.json', '2 Timotheos'),
  BookEntry('Yehouda (Jude)', 'Jd.', '61-Jude.json'),
  BookEntry('Hébreux', 'Hé.', '62-Hebreux.json', 'Ivriyim'),
  BookEntry('1 Jean', '1 Jn.', '63-1Jean.json', '1 Yohanan'),
  BookEntry('2 Jean', '2 Jn.', '64-2Jean.json', '2 Yohanan'),
  BookEntry('3 Jean', '3 Jn.', '65-3Jean.json', '3 Yohanan'),
  BookEntry('Apocalypse', 'Ap.', '66-Apocalypse.json', 'Apokalupsis'),
];

BookEntry catalogEntry(int bymIndex) => bookCatalog[bymIndex - 1];
