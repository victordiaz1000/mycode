/// Le corps HTML d'une page de glossaire (`notes.json`), démonté en blocs.
///
/// La source écrit du HTML de navigateur : tables non fermées, `<p>` sans
/// `</p>`, `&nbsp;` par triplet, hébreu dans `<font face="Ezra SIL">`, liens
/// vers le lexique (`h.php?c=STR&f=H7225`), vers une autre page de glossaire
/// (`g.php?v=ATI&g=Difficulté 7`) et vers un verset de la LSGS
/// (`r.php?v=LSG&r=GEN1.2`). Ce module le démonte **sans rien réécrire** :
/// il rend un arbre de blocs et de fragments que `ati_note_view.dart` pose à
/// l'écran, les trois sortes de liens gardées comme telles pour y rester
/// cliquables.
///
/// Tolérant par principe : un tag inconnu est ignoré, un bloc non fermé est
/// refermé à la fin du flux. Une page abîmée doit se lire en partie, pas faire
/// tomber l'écran.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Une page déjà démontée.
final class AtiNoteDocument {
  const AtiNoteDocument({required this.nodes});

  /// Les blocs dans l'ordre du document.
  final List<AtiNoteNode> nodes;

  /// Pas de contenu : la fiche affiche alors son titre seul.
  bool get isEmpty => nodes.isEmpty;

  static AtiNoteDocument parse(String html) => _Parser(html).parse();
}

// --- Blocs ------------------------------------------------------------------

sealed class AtiNoteNode {
  const AtiNoteNode();
}

/// `<h1>` (titre de page) ou `<h3>` (sous-titre).
final class AtiNoteHeading extends AtiNoteNode {
  const AtiNoteHeading({required this.level, required this.spans});

  /// 1 ou 3, le niveau de la balise d'origine.
  final int level;
  final List<AtiNoteSpan> spans;
}

/// Un paragraphe. [quote] le met en retrait : c'est un `<blockquote>`, où la
/// source pose ses citations de versets.
final class AtiNoteParagraph extends AtiNoteNode {
  const AtiNoteParagraph({required this.spans, this.quote = false});

  final List<AtiNoteSpan> spans;
  final bool quote;
}

/// `<ul>` — la source s'en sert pour les listes d'emplois (`<li>`).
final class AtiNoteList extends AtiNoteNode {
  const AtiNoteList({required this.items});

  final List<List<AtiNoteSpan>> items;
}

/// `<table>` — le corps des pages : une référence de verset, son hébreu, sa
/// traduction, et dans `abr` deux colonnes d'abréviations.
final class AtiNoteTable extends AtiNoteNode {
  const AtiNoteTable({required this.rows});

  final List<AtiNoteRow> rows;
}

final class AtiNoteRow {
  const AtiNoteRow({required this.cells});

  final List<AtiNoteCell> cells;
}

final class AtiNoteCell {
  const AtiNoteCell({required this.spans, this.right = false, this.width});

  final List<AtiNoteSpan> spans;

  /// `align="right"` : la source aligne ses références de verset à droite de
  /// la colonne.
  final bool right;

  /// `width=200` en pixels, borne indicative — pas une largeur imposée.
  final int? width;
}

/// `<hr>`.
final class AtiNoteRule extends AtiNoteNode {
  const AtiNoteRule();
}

/// `<img src="data:image/jpeg;base64,…">` : deux schémas morphologiques dans
/// `r2`, écrits en dur dans la page.
final class AtiNoteImage extends AtiNoteNode {
  const AtiNoteImage({required this.bytes, this.bordered = false});

  /// Les octets décodés, prêts pour `Image.memory`.
  final Uint8List bytes;
  final bool bordered;
}

// --- Fragments --------------------------------------------------------------

sealed class AtiNoteSpan {
  const AtiNoteSpan();
}

/// Les marques typographiques portées par un fragment, telles que la source
/// les empile (`<b><sup><a …>`). Une seule classe plutôt que cinq sous-classes
/// : tout fragment peut en porter plusieurs à la fois.
class AtiNoteTextStyle {
  const AtiNoteTextStyle({
    this.italic = false,
    this.bold = false,
    this.big = false,
    this.sup = false,
    this.hebrew = false,
  });

  final bool italic;
  final bool bold;

  /// `<big>` — la source grossit les traductions dans ses tableaux.
  final bool big;

  /// `<sup>` — les abréviations morphologiques (`►InCs`).
  final bool sup;

  /// `<font face="Ezra SIL">` : hébreu. Ezra SIL n'est pas embarquée, Cardo
  /// l'est et couvre les points-voyelles — voir `AtiInterlinear.cardoFamily`.
  final bool hebrew;

  AtiNoteTextStyle merged(AtiNoteTextStyle other) => AtiNoteTextStyle(
    italic: italic || other.italic,
    bold: bold || other.bold,
    big: big || other.big,
    sup: sup || other.sup,
    hebrew: hebrew || other.hebrew,
  );

  @override
  bool operator ==(Object other) =>
      other is AtiNoteTextStyle &&
      other.italic == italic &&
      other.bold == bold &&
      other.big == big &&
      other.sup == sup &&
      other.hebrew == hebrew;

  @override
  int get hashCode => Object.hash(italic, bold, big, sup, hebrew);

  bool get isPlain => !italic && !bold && !big && !sup && !hebrew;
}

final class AtiNoteText extends AtiNoteSpan {
  const AtiNoteText(this.text, {this.style = const AtiNoteTextStyle()});

  final String text;
  final AtiNoteTextStyle style;
}

/// Où un lien de page mène. Trois sortes, celles que la source écrit :
/// le lexique, une autre page du glossaire, un verset de la LSGS.
sealed class AtiNoteTarget {
  const AtiNoteTarget();
}

/// `h.php?c=STR&f=H7225` — le même lexique Strong que la LSGS.
final class AtiNoteStrongTarget extends AtiNoteTarget {
  const AtiNoteStrongTarget(this.strong);

  final String strong;

  @override
  bool operator ==(Object other) =>
      other is AtiNoteStrongTarget && other.strong == strong;

  @override
  int get hashCode => strong.hashCode;
}

/// `g.php?v=ATI&g=Difficulté 7` — nom d'une autre page du glossaire. C'est le
/// **nom** (`AtiNote.name`), pas l'identifiant : le résoudre est le travail de
/// `AtiNotes`, pas du démontage.
final class AtiNotePageTarget extends AtiNoteTarget {
  const AtiNotePageTarget(this.pageName);

  final String pageName;

  @override
  bool operator ==(Object other) =>
      other is AtiNotePageTarget && other.pageName == pageName;

  @override
  int get hashCode => pageName.hashCode;
}

/// `r.php?v=LSG&r=GEN1.2` — un verset, en code OSIS suivi de `chapitre.verset`.
final class AtiNoteVerseTarget extends AtiNoteTarget {
  const AtiNoteVerseTarget(this.osis);

  final String osis;

  @override
  bool operator ==(Object other) =>
      other is AtiNoteVerseTarget && other.osis == osis;

  @override
  int get hashCode => osis.hashCode;
}

final class AtiNoteLink extends AtiNoteSpan {
  const AtiNoteLink(
    this.target,
    this.label, {
    this.style = const AtiNoteTextStyle(),
  });

  final AtiNoteTarget target;
  final String label;
  final AtiNoteTextStyle style;
}

/// Un saut de ligne forcé (`<br>`).
final class AtiNoteLineBreak extends AtiNoteSpan {
  const AtiNoteLineBreak();
}

// --- Démontage --------------------------------------------------------------

final class _Parser {
  _Parser(this.html);

  final String html;

  final List<AtiNoteNode> nodes = [];

  /// Le fragment du bloc en cours : paragraphe, titre, `<li>` — `null` hors
  /// bloc. Une cellule de tableau possède la sienne, qui la prime.
  List<AtiNoteSpan>? _spans;
  _BlockKind _kind = _BlockKind.none;
  int _headingLevel = 1;
  bool _quote = false;
  List<List<AtiNoteSpan>>? _list;

  _TableBuilder? _table;
  _RowBuilder? _row;
  _CellBuilder? _cell;

  /// La pile des balises en ligne ouvertes : style et lien s'y cumulent.
  final List<_Frame> _frames = [];

  static final RegExp _token = RegExp(r'<[^>]*>|[^<]+');
  static final RegExp _tagHead = RegExp(r'^<\s*(/?)\s*([a-zA-Z][a-zA-Z0-9]*)');
  static final RegExp _attr = RegExp(
    r'([a-zA-Z][a-zA-Z-]*)\s*=\s*("([^"]*)"|[^\s>]+)',
  );

  AtiNoteDocument parse() {
    for (final match in _token.allMatches(html)) {
      final raw = match.group(0)!;
      if (raw.startsWith('<')) {
        _tag(raw);
      } else {
        _text(raw);
      }
    }
    _flush();
    _flushList();
    _flushTable();
    return AtiNoteDocument(nodes: nodes);
  }

  // Le fragment qui reçoit le texte : la cellule d'abord, sinon le bloc.
  List<AtiNoteSpan>? get _target => _cell?.spans ?? _spans;

  void _text(String raw) {
    final decoded = raw.replaceAll('&nbsp;', ' ').replaceAll('&amp;', '&');
    if (_target == null) {
      // Du texte entre deux blocs : c'est de l'indentation de source, sauf
      // s'il porte du contenu, auquel cas la page a un paragraphe sans `<p>`.
      if (decoded.trim().isEmpty) return;
      _openBlock(_BlockKind.paragraph);
    }
    final spans = _target!;
    if (decoded.trim().isEmpty) {
      // Une balise en ligne posée entre deux mots : une espace, une seule.
      if (spans.isEmpty) return;
      final last = spans.last;
      if (last is AtiNoteText) {
        if (!last.text.endsWith(' ')) {
          spans[spans.length - 1] = AtiNoteText(
            '${last.text} ',
            style: last.style,
          );
        }
      } else {
        // Une espace juste après un lien, sinon le lien et le mot suivant
        // se collent.
        spans.add(const AtiNoteText(' '));
      }
      return;
    }
    // Le blanc de début de fragment ne sert que si un fragment le précède :
    // `mot<i>suit</i>` reste collé, `mot <i>suit</i>` garde son espace.
    final kept = spans.isEmpty ? decoded.trimLeft() : decoded;
    final style = _style;
    final link = _link;
    if (link != null) {
      final label = kept.trim();
      final last = spans.isNotEmpty ? spans.last : null;
      if (last is AtiNoteLink && last.target == link && last.style == style) {
        // Le libellé d'un lien peut être coupé en deux par une balise en
        // ligne : un seul fragment, sinon le tap se scinde.
        spans[spans.length - 1] = AtiNoteLink(
          link,
          '${last.label}$label',
          style: style,
        );
        return;
      }
      spans.add(AtiNoteLink(link, label, style: style));
      return;
    }
    final last = spans.isNotEmpty ? spans.last : null;
    if (last is AtiNoteText && last.style == style) {
      // Fusionner : `<big>mot</big>` suivi d'un texte nu doit faire un seul
      // fragment, sinon l'interligne se démultiplie.
      spans[spans.length - 1] = AtiNoteText('${last.text}$kept', style: style);
      return;
    }
    spans.add(AtiNoteText(kept, style: style));
  }

  /// Retire l'espace de fin de bloc : il vient du balisage, pas du propos.
  static void _trimEnd(List<AtiNoteSpan> spans) {
    while (spans.isNotEmpty) {
      final last = spans.last;
      if (last is! AtiNoteText) return;
      final trimmed = last.text.trimRight();
      if (trimmed.isEmpty) {
        spans.removeLast();
        continue;
      }
      spans[spans.length - 1] = AtiNoteText(trimmed, style: last.style);
      return;
    }
  }

  void _tag(String raw) {
    final head = _tagHead.firstMatch(raw);
    if (head == null) return;
    final closing = head.group(1) == '/';
    final name = head.group(2)!.toLowerCase();
    final attrs = closing ? const <String, String>{} : _attrs(raw);

    if (!closing) {
      switch (name) {
        case 'html':
        case 'head':
        case 'body':
        case 'meta':
        case 'title':
          return;
        case 'h1':
          _openBlock(_BlockKind.heading, level: 1);
        case 'h3':
          _openBlock(_BlockKind.heading, level: 3);
        case 'p':
          _openBlock(_BlockKind.paragraph);
        case 'blockquote':
          _flush();
          _quote = true;
        case 'ul':
          _flush();
          _list ??= <List<AtiNoteSpan>>[];
        case 'li':
          _openBlock(_BlockKind.listItem);
        case 'table':
          _flush();
          _flushTable();
          _table = _TableBuilder();
        case 'tr':
          _flushRow();
          _row = _RowBuilder();
        case 'td':
        case 'th':
          _flushCell();
          _row ??= _RowBuilder();
          _cell = _CellBuilder(
            right: attrs['align'] == 'right',
            width: int.tryParse(attrs['width'] ?? ''),
          );
        case 'br':
          if (_target == null) _openBlock(_BlockKind.paragraph);
          _target!.add(const AtiNoteLineBreak());
        case 'hr':
          _flush();
          nodes.add(const AtiNoteRule());
        case 'img':
          _flush();
          final bytes = _imageBytes(attrs['src'] ?? '');
          if (bytes != null) {
            nodes.add(
              AtiNoteImage(bytes: bytes, bordered: attrs['border'] != null),
            );
          }
        case 'b':
        case 'strong':
          _frames.add(const _Frame(style: AtiNoteTextStyle(bold: true)));
        case 'i':
        case 'em':
          _frames.add(const _Frame(style: AtiNoteTextStyle(italic: true)));
        case 'big':
          _frames.add(const _Frame(style: AtiNoteTextStyle(big: true)));
        case 'sup':
          _frames.add(const _Frame(style: AtiNoteTextStyle(sup: true)));
        case 'font':
          _frames.add(
            _Frame(
              style: AtiNoteTextStyle(hebrew: attrs['face'] == 'Ezra SIL'),
            ),
          );
        case 'span':
          _frames.add(const _Frame());
        case 'a':
          _frames.add(_Frame(link: _targetOf(attrs)));
        default:
          break;
      }
      return;
    }

    switch (name) {
      case 'p':
      case 'h1':
      case 'h3':
      case 'li':
        _flush();
      case 'blockquote':
        _flush();
        _quote = false;
      case 'ul':
        _flush();
        _flushList();
      case 'td':
      case 'th':
        _flushCell();
      case 'tr':
        _flushCell();
        _flushRow();
      case 'table':
        _flush();
        _flushTable();
      case 'b':
      case 'strong':
      case 'i':
      case 'em':
      case 'big':
      case 'sup':
      case 'font':
      case 'span':
      case 'a':
        if (_frames.isNotEmpty) _frames.removeLast();
      default:
        break;
    }
  }

  /// Les attributs d'une balise, non cités compris (`width=200`) : la source
  /// en écrit certains sans guillemets.
  Map<String, String> _attrs(String raw) {
    final attrs = <String, String>{};
    for (final match in _attr.allMatches(raw)) {
      attrs[match.group(1)!.toLowerCase()] =
          match.group(3) ?? match.group(2) ?? '';
    }
    return attrs;
  }

  /// L'adresse d'un `<a>` : lexique, glossaire ou verset. Un lien que la
  /// source écrit ailleurs devient `null` et se lit en texte.
  AtiNoteTarget? _targetOf(Map<String, String> attrs) {
    final href = attrs['href'] ?? '';
    if (href.contains('h.php')) {
      final strong = RegExp(r'[GH]\d+').firstMatch(href);
      return strong != null ? AtiNoteStrongTarget(strong.group(0)!) : null;
    }
    if (href.contains('g.php')) {
      final page = attrs['g'] ?? _pageOf(href);
      return page.isEmpty ? null : AtiNotePageTarget(page);
    }
    if (href.contains('r.php')) {
      final osis = RegExp(r'[?&]r=([^&]+)').firstMatch(href)?.group(1) ?? '';
      return osis.isEmpty ? null : AtiNoteVerseTarget(osis);
    }
    return null;
  }

  /// Le nom de page porté par une adresse `g.php?…&g=Difficulté 7`.
  ///
  /// La source y écrit ses accents **bruts**, et `Uri.decodeQueryComponent`
  /// refuse les caractères hors ASCII : on ne décode que si l'adresse porte
  /// réellement un `%`, et l'on garde le brut si même là ça échoue. Un nom
  /// déformé ne vaut pas une page qui refuse de s'ouvrir.
  static String _pageOf(String href) {
    final raw = RegExp(r'[?&]g=([^&]+)').firstMatch(href)?.group(1) ?? '';
    if (!raw.contains('%')) return raw;
    try {
      return Uri.decodeQueryComponent(raw);
    } catch (_) {
      return raw;
    }
  }

  static Uint8List? _imageBytes(String src) {
    final marker = 'base64,';
    final index = src.indexOf(marker);
    if (index < 0) return null;
    try {
      // La source coupe ses base64 en fin de ligne : sans ce nettoyage le
      // décodeur refuse le retour à la ligne et le schéma disparaît.
      return base64Decode(
        src.substring(index + marker.length).replaceAll(RegExp(r'\s'), ''),
      );
    } catch (_) {
      return null;
    }
  }

  AtiNoteTextStyle get _style {
    var style = const AtiNoteTextStyle();
    for (final frame in _frames) {
      style = style.merged(frame.style);
    }
    return style;
  }

  AtiNoteTarget? get _link {
    AtiNoteTarget? link;
    for (final frame in _frames) {
      if (frame.link != null) link = frame.link;
    }
    return link;
  }

  void _openBlock(_BlockKind kind, {int level = 1}) {
    _flush();
    _spans = <AtiNoteSpan>[];
    _kind = kind;
    if (kind == _BlockKind.heading) _headingLevel = level;
    if (kind == _BlockKind.listItem) _list ??= <List<AtiNoteSpan>>[];
  }

  /// Referme le bloc ouvert, s'il porte du contenu.
  void _flush() {
    final spans = _spans;
    if (spans != null && spans.isNotEmpty) {
      _trimEnd(spans);
      if (spans.isNotEmpty) {
        switch (_kind) {
          case _BlockKind.heading:
            nodes.add(AtiNoteHeading(level: _headingLevel, spans: spans));
          case _BlockKind.listItem:
            _list!.add(spans);
          case _BlockKind.paragraph:
            nodes.add(AtiNoteParagraph(spans: spans, quote: _quote));
          case _BlockKind.none:
            break;
        }
      }
    }
    _spans = null;
    _kind = _BlockKind.none;
  }

  void _flushList() {
    final list = _list;
    if (list == null) return;
    if (list.isNotEmpty) nodes.add(AtiNoteList(items: list));
    _list = null;
  }

  void _flushCell() {
    final row = _row;
    final cell = _cell;
    if (row != null && cell != null) {
      _trimEnd(cell.spans);
      // Une cellule vide est une colonne vide, pas une cellule perdue : la
      // source s'en sert d'intercolonne (`<td width=30>`).
      row.cells.add(
        AtiNoteCell(spans: cell.spans, right: cell.right, width: cell.width),
      );
    }
    _cell = null;
  }

  void _flushRow() {
    _flushCell();
    final table = _table;
    final row = _row;
    if (table != null && row != null && row.cells.isNotEmpty) {
      table.rows.add(AtiNoteRow(cells: row.cells));
    }
    _row = null;
  }

  void _flushTable() {
    _flushRow();
    final table = _table;
    if (table != null && table.rows.isNotEmpty) {
      nodes.add(AtiNoteTable(rows: table.rows));
    }
    _table = null;
  }
}

enum _BlockKind { none, paragraph, heading, listItem }

final class _Frame {
  const _Frame({this.style = const AtiNoteTextStyle(), this.link});

  final AtiNoteTextStyle style;
  final AtiNoteTarget? link;
}

final class _TableBuilder {
  final List<AtiNoteRow> rows = [];
}

final class _RowBuilder {
  final List<AtiNoteCell> cells = [];
}

final class _CellBuilder {
  _CellBuilder({required this.right, this.width});

  final bool right;
  final int? width;
  final List<AtiNoteSpan> spans = [];
}
