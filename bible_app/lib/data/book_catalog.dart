class BookEntry {
  final String name;
  final String abbreviation;
  final String file;

  const BookEntry(this.name, this.abbreviation, this.file);

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
  BookEntry('Amos', 'Am.', '17-Amos.json'),
  BookEntry('Ovadia (Abdias)', 'Ab.', '18-Abdias.json'),
  BookEntry('Yonah (Jonas)', 'Jon.', '19-Jonas.json'),
  BookEntry('Mikha (Michée)', 'Mi.', '20-Michee.json'),
  BookEntry('Nahum', 'Na.', '21-Nahum.json'),
  BookEntry('Habakuk', 'Ha.', '22-Habakuk.json'),
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
  BookEntry('Esther', 'Est.', '34-Esther.json'),
  BookEntry('Daniel', 'Da.', '35-Daniel.json'),
  BookEntry('Ezra (Esdras)', 'Esd.', '36-Esdras.json'),
  BookEntry('Nehemia (Néhémie)', 'Né.', '37-Nehemie.json'),
  BookEntry('Divrei Hayamim 1 (1 Chroniques)', '1 Ch.', '38-1Chroniques.json'),
  BookEntry('Divrei Hayamim 2 (2 Chroniques)', '2 Ch.', '39-2Chroniques.json'),
  BookEntry('Matthieu', 'Mt.', '40-Matthieu.json'),
  BookEntry('Marc', 'Mc.', '41-Marc.json'),
  BookEntry('Luc', 'Lc.', '42-Luc.json'),
  BookEntry('Jean', 'Jn.', '43-Jean.json'),
  BookEntry('Actes', 'Ac.', '44-Actes.json'),
  BookEntry('Yaacov (Jacques)', 'Ja.', '45-Jacques.json'),
  BookEntry('Galates', 'Ga.', '46-Galates.json'),
  BookEntry('1 Thessaloniciens', '1 Th.', '47-1Thessaloniciens.json'),
  BookEntry('2 Thessaloniciens', '2 Th.', '48-2Thessaloniciens.json'),
  BookEntry('1 Corinthiens', '1 Co.', '49-1Corinthiens.json'),
  BookEntry('2 Corinthiens', '2 Co.', '50-2Corinthiens.json'),
  BookEntry('Romains', 'Ro.', '51-Romains.json'),
  BookEntry('Éphésiens', 'Ép.', '52-Ephesiens.json'),
  BookEntry('Philippiens', 'Ph.', '53-Philippiens.json'),
  BookEntry('Colossiens', 'Col.', '54-Colossiens.json'),
  BookEntry('Philémon', 'Phm.', '55-Philemon.json'),
  BookEntry('1 Timothée', '1 Ti.', '56-1Timothee.json'),
  BookEntry('Tite', 'Tit.', '57-Tite.json'),
  BookEntry('1 Pierre', '1 Pi.', '58-1Pierre.json'),
  BookEntry('2 Pierre', '2 Pi.', '59-2Pierre.json'),
  BookEntry('2 Timothée', '2 Ti.', '60-2Timothee.json'),
  BookEntry('Yehouda (Jude)', 'Jd.', '61-Jude.json'),
  BookEntry('Hébreux', 'Hé.', '62-Hebreux.json'),
  BookEntry('1 Jean', '1 Jn.', '63-1Jean.json'),
  BookEntry('2 Jean', '2 Jn.', '64-2Jean.json'),
  BookEntry('3 Jean', '3 Jn.', '65-3Jean.json'),
  BookEntry('Apocalypse', 'Ap.', '66-Apocalypse.json'),
];

BookEntry catalogEntry(int bymIndex) => bookCatalog[bymIndex - 1];
