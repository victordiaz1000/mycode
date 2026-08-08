class BibleSection {
  final String name;
  final int from; // first BYM index (1-based)
  final int to; // last BYM index (inclusive)
  final String subtitle;

  const BibleSection({
    required this.name,
    required this.from,
    required this.to,
    required this.subtitle,
  });

  bool contains(int bymIndex) => bymIndex >= from && bymIndex <= to;
}

/// The five top-level sections of the app (no OT/NT split, per design).
const List<BibleSection> bibleSections = [
  BibleSection(name: 'Torah', from: 1, to: 5, subtitle: 'Genèse → Deutéronome'),
  BibleSection(
      name: 'Nevi’im / Prophètes',
      from: 6,
      to: 26,
      subtitle: 'Josué → Malachie'),
  BibleSection(
      name: 'Ketouvim / Écrits', from: 27, to: 39, subtitle: 'Psaumes → 2 Chroniques'),
  BibleSection(name: 'Évangiles', from: 40, to: 43, subtitle: 'Matthieu → Jean'),
  BibleSection(
      name: 'Testament de Yehoshoua',
      from: 44,
      to: 66,
      subtitle: 'Actes → Apocalypse'),
];

BibleSection sectionForBook(int bymIndex) =>
    bibleSections.firstWhere((s) => s.contains(bymIndex));
