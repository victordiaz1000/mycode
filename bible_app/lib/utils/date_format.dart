const List<String> _weekdays = [
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];

/// "il y a 5 min", "hier, 21:14", "lundi", "12/03".
String formatRelativeDate(DateTime when, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final delta = ref.difference(when);
  if (delta.inMinutes < 1) return 'à l’instant';
  if (delta.inMinutes < 60) return 'il y a ${delta.inMinutes} min';

  final day = DateTime(when.year, when.month, when.day);
  final today = DateTime(ref.year, ref.month, ref.day);
  final days = today.difference(day).inDays;
  final hhmm =
      '${when.hour.toString().padLeft(2, '0')}:'
      '${when.minute.toString().padLeft(2, '0')}';
  if (days <= 0) return 'aujourd’hui, $hhmm';
  if (days == 1) return 'hier, $hhmm';
  if (days < 7) return _weekdays[when.weekday - 1];
  return '${when.day.toString().padLeft(2, '0')}/'
      '${when.month.toString().padLeft(2, '0')}';
}