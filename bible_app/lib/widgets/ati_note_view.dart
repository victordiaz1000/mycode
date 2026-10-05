import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/ati_note_html.dart';
import 'ati_interlinear.dart' show AtiInterlinear;
import 'premium_style.dart';

/// Le corps d'une page de glossaire, posé à l'écran.
///
/// Les blocs viennent tout démontés de `AtiNoteDocument` : ce widget ne fait
/// que les mettre en lumière — la même lumière que les fiches d'étude
/// (`premiumPalette`, `premiumSurface`), la même police de lecture que le
/// reste des articles, et l'hébreu de la source rendu en Cardo faute d'Ezra
/// SIL embarquée.
///
/// Les trois sortes de liens ressortent telles quelles : le code Strong ouvre
/// la fiche du lexique, le renvoi de glossaire pousse l'autre page, et un
/// verset de la LSGS se lit si — et seulement si — l'appelant sait l'ouvrir.
/// Un lien sans appelant reste du texte : pas de promesse de tap que
/// personne ne tiendrait.
class AtiNoteView extends StatelessWidget {
  const AtiNoteView({
    super.key,
    required this.document,
    this.fontSize = 15,
    this.fontFamily,
    this.onStrongTap,
    this.onPageTap,
    this.onVerseTap,
  });

  /// La page démontée.
  final AtiNoteDocument document;

  /// Taille et police du corps, telles que les réglages de fiche les donnent.
  final double fontSize;
  final String? fontFamily;

  /// Ouvre la fiche du lexique Strong — signature celle de la LSGS, où le
  /// même appelant fait le même travail.
  final void Function(String strong)? onStrongTap;

  /// Ouvre une autre page du glossaire, par son intitulé (`Difficulté 7`).
  final void Function(String pageName)? onPageTap;

  /// Ouvre un verset de la LSGS, en code OSIS (`GEN1.2`). Non branché : la
  /// référence se lit, elle ne se presse pas.
  final void Function(String osis)? onVerseTap;

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    final base = TextStyle(
      fontFamily: fontFamily ?? kUiFontFamily,
      fontSize: fontSize,
      height: 1.6,
      color: p.onSurface,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final node in document.nodes)
              _node(context, node, base, p, width),
          ],
        );
      },
    );
  }

  // --- Blocs ----------------------------------------------------------------

  Widget _node(
    BuildContext context,
    AtiNoteNode node,
    TextStyle base,
    PremiumPalette p,
    double width,
  ) => switch (node) {
    AtiNoteHeading(:final level, :final spans) => Padding(
      padding: EdgeInsets.only(top: level == 1 ? 0 : 20, bottom: 10),
      child: Text.rich(
        TextSpan(children: [_spans(spans, base, p)]),
        style: level == 1
            ? base.merge(
                premiumText(
                  context,
                  fontSize * 1.35,
                  FontWeight.w800,
                  p.textDark,
                ),
              )
            : base.merge(
                premiumText(
                  context,
                  fontSize * 1.12,
                  FontWeight.w700,
                  p.textDark,
                ),
              ),
      ),
    ),
    AtiNoteParagraph(:final spans, :final quote) => Padding(
      padding: EdgeInsets.only(bottom: 10, left: quote ? 14 : 0),
      child: Container(
        width: double.infinity,
        padding: quote ? const EdgeInsets.only(left: 12) : EdgeInsets.zero,
        decoration: quote
            ? BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: p.textGrey.withValues(alpha: .35),
                    width: 2,
                  ),
                ),
              )
            : null,
        child: Text.rich(
          TextSpan(children: [_spans(spans, base, p)]),
          style: base,
        ),
      ),
    ),
    AtiNoteList(:final items) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: base.copyWith(color: p.primary)),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [_spans(item, base, p)]),
                      style: base,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
    AtiNoteTable(:final rows) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _table(context, rows, base, p, width),
    ),
    AtiNoteRule() => Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Divider(height: 1, color: p.textGrey.withValues(alpha: .3)),
    ),
    AtiNoteImage(:final bytes, :final bordered) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(bordered ? 8 : 0),
          child: Image.memory(
            bytes,
            width: width,
            fit: BoxFit.contain,
            // Un schéma illisible ne doit pas faire tomber la page.
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      ),
    ),
  };

  // --- Fragments ------------------------------------------------------------

  /// Les fragments d'un bloc, dans la couleur de la page.
  InlineSpan _spans(
    List<AtiNoteSpan> spans,
    TextStyle base,
    PremiumPalette p,
  ) => TextSpan(children: [for (final span in spans) _span(span, base, p)]);

  InlineSpan _span(AtiNoteSpan span, TextStyle base, PremiumPalette p) =>
      switch (span) {
        AtiNoteLineBreak() => const TextSpan(text: '\n'),
        AtiNoteText(:final text, :final style) => TextSpan(
          text: text,
          style: _delta(style, base.fontSize ?? 15),
        ),
        AtiNoteLink(:final target, :final label, :final style) => _link(
          target,
          label,
          base,
          _delta(style, base.fontSize ?? 15),
          p,
        ),
      };

  /// Ce qu'une balise en ligne ajoute au corps. Les tailles se cumulent sur
  /// celle du corps : `<big>` grossit, `<sup>` rapetisse, l'hébreu passe en
  /// Cardo et prend un peu d'air — les points-voyelles s'y lisent mal tassés.
  TextStyle _delta(AtiNoteTextStyle style, double size) {
    var delta = const TextStyle();
    if (style.italic) delta = delta.copyWith(fontStyle: FontStyle.italic);
    if (style.bold) delta = delta.copyWith(fontWeight: FontWeight.w700);
    if (style.hebrew) {
      delta = delta.copyWith(
        fontFamily: AtiInterlinear.cardoFamily,
        fontSize: size * 1.08,
      );
    }
    if (style.big) {
      delta = delta.copyWith(fontSize: (delta.fontSize ?? size) * 1.15);
    }
    if (style.sup) {
      delta = delta.copyWith(fontSize: (delta.fontSize ?? size) * .78);
    }
    return delta;
  }

  /// Un lien : tappable si l'appelant sait ouvrir sa cible, texte courant
  /// sinon. Le WidgetSpan évite les `TapGestureRecognizer` à libérer — la
  /// page est longue et se rebâtit à chaque réglage de taille de texte.
  InlineSpan _link(
    AtiNoteTarget target,
    String label,
    TextStyle base,
    TextStyle delta,
    PremiumPalette p,
  ) {
    final void Function()? onTap = switch (target) {
      AtiNoteStrongTarget(:final strong) =>
        onStrongTap == null ? null : () => onStrongTap!(strong),
      AtiNotePageTarget(:final pageName) =>
        onPageTap == null ? null : () => onPageTap!(pageName),
      AtiNoteVerseTarget(:final osis) =>
        onVerseTap == null ? null : () => onVerseTap!(osis),
    };
    if (onTap == null) {
      return TextSpan(text: label, style: delta);
    }
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Text(
          label,
          style: base
              .merge(delta)
              .copyWith(
                color: p.primary,
                decoration: TextDecoration.underline,
                decorationStyle: TextDecorationStyle.dotted,
                decorationColor: p.primary.withValues(alpha: .7),
              ),
        ),
      ),
    );
  }

  // --- Tableaux -------------------------------------------------------------

  /// La mise en page des tableaux de la source : la référence de verset à
  /// gauche sur sa largeur déclarée, l'hébreu et la traduction à droite, la
  /// traduction de la ligne suivante alignée sous l'hébreu — ce que le
  /// navigateur obtient avec ses colonnes et que `Table` obtient ici avec les
  /// mêmes largeurs.
  ///
  /// Une colonne que la source dimensionne (`width=200`) est fixée, bornée à
  /// 55 % de la largeur utile pour qu'aucune page ne déborde ; les autres se
  /// partagent le reste.
  Widget _table(
    BuildContext context,
    List<AtiNoteRow> rows,
    TextStyle base,
    PremiumPalette p,
    double maxWidth,
  ) {
    var columns = 0;
    for (final row in rows) {
      columns = math.max(columns, row.cells.length);
    }
    if (columns == 0) return const SizedBox.shrink();

    final fixed = List<double?>.filled(columns, null);
    for (final row in rows) {
      for (var i = 0; i < row.cells.length && i < columns; i++) {
        final declared = row.cells[i].width;
        if (declared == null) continue;
        final current = fixed[i];
        if (current == null || declared > current) {
          fixed[i] = declared.toDouble();
        }
      }
    }
    final declaredTotal = fixed.whereType<double>().fold<double>(
      0,
      (sum, w) => sum + w,
    );
    final cap = maxWidth * .55;
    final scale = declaredTotal > cap && declaredTotal > 0
        ? cap / declaredTotal
        : 1.0;

    return Table(
      columnWidths: {
        for (var i = 0; i < columns; i++)
          if (fixed[i] != null) i: FixedColumnWidth(fixed[i]! * scale),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        for (final row in rows)
          TableRow(
            children: [
              for (var i = 0; i < columns; i++)
                _cell(i < row.cells.length ? row.cells[i] : null, base, p),
            ],
          ),
      ],
    );
  }

  Widget _cell(AtiNoteCell? cell, TextStyle base, PremiumPalette p) {
    if (cell == null || cell.spans.isEmpty) return const SizedBox(height: 14);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      child: Align(
        alignment: cell.right ? Alignment.centerRight : Alignment.centerLeft,
        child: Text.rich(
          TextSpan(children: [_spans(cell.spans, base, p)]),
          style: base,
          textAlign: cell.right ? TextAlign.right : TextAlign.left,
        ),
      ),
    );
  }
}
