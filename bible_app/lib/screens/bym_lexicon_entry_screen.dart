import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../data/book_catalog.dart';
import '../data/lexicon_index.dart';
import '../data/note_reference_linker.dart';
import '../data/reference_parser.dart';
import '../widgets/bible_theme_scope.dart';
import '../widgets/fiche_header.dart';
import '../widgets/fiche_text_settings.dart';
import '../widgets/premium_style.dart';

/// A single entry of the BYM lexicon: the anchored word in a pinned header,
/// its note definition on the page background, and where it was first met.
/// The reference opens the verse in the reader through [onOpenVerse].
///
/// The Bible references embedded in the definition are rendered exactly like
/// the note references of the reading screen — accent colour, dotted
/// underline, background tint — and tappable towards the verse they name.
///
/// Maquette `maquette_fiches_mot.html` §03 : trois cadres pour un paragraphe
/// (bandeau vide, carte à dégradé, étiquette « Définition », définition
/// re-encadrée). Le mot devient le titre de la page et reste visible au
/// défilement, la référence et le compte passent en ligne de métadonnées, et
/// le fond de page porte le texte — seuls les renvois gardent leur mise en
/// valeur.
class BymLexiconEntryScreen extends StatefulWidget {
  final DictionaryEntry entry;

  /// Opens the referenced verse in a reader tab. Null when the screen stands
  /// alone (tests): the button then states the reference without navigating,
  /// and the definition keeps its references as plain text — a recognizer
  /// that answers to nothing is a button-shaped lie.
  final void Function(int bookIndex, int chapter, int verse)? onOpenVerse;

  /// Étape G : posée en volet d'un split-view, la fiche ne montre pas de
  /// retour — il dépilerait l'écran qui l'héberge. Vrai par défaut (route).
  final bool showBackButton;

  const BymLexiconEntryScreen({
    super.key,
    required this.entry,
    this.onOpenVerse,
    this.showBackButton = true,
  });

  @override
  State<BymLexiconEntryScreen> createState() => _BymLexiconEntryScreenState();
}

class _BymLexiconEntryScreenState extends State<BymLexiconEntryScreen> {
  String get _reference {
    final abbr = catalogEntry(widget.entry.bookIndex).abbreviation;
    return '$abbr ${widget.entry.chapter}:${widget.entry.verseNumber}';
  }

  String get _metaline => widget.entry.occurrences > 1
      ? '$_reference · ${widget.entry.occurrences} occurrences'
      : _reference;

  @override
  Widget build(BuildContext context) {
    // Famille `dico.*`, comme les autres fiches de dictionnaire.
    return FicheTextScope(
      group: DisplayGroup.dico,
      builder: (context, style) => _scaffold(context, style),
    );
  }

  Widget _scaffold(BuildContext context, FicheTextStyle style) {
    final p = premiumPalette(context);
    return Scaffold(
      backgroundColor: premiumBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: p.textDark,
        centerTitle: true,
        automaticallyImplyLeading: widget.showBackButton,
        actions: const [FicheDisplayMenuButton(group: DisplayGroup.dico)],
      ),
      // En-tête épinglée, comme les autres fiches de mot : pas de problème
      // de performance ici, le `CustomScrollView` ne sert que l'épinglage.
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: FicheHeader(
                title: Text(
                  widget.entry.word,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: premiumText(
                    context,
                    18,
                    FontWeight.w800,
                    p.textDark,
                    spacing: 0.6,
                  ),
                ),
                badge: 'Notes BYM Lexique',
                note: widget.entry.occurrences > 1
                    ? '${widget.entry.occurrences} occurrences'
                    : null,
                palette: p,
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _metaline,
                      style: premiumText(
                        context,
                        12,
                        FontWeight.w500,
                        p.textGrey,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _BymDefinition(
                      definition: widget.entry.definition,
                      onOpenVerse: widget.onOpenVerse,
                      style: style,
                    ),
                    const SizedBox(height: 24),
                    if (widget.onOpenVerse != null)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: p.primary,
                            foregroundColor: p.onPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () => widget.onOpenVerse!(
                            widget.entry.bookIndex,
                            widget.entry.chapter,
                            widget.entry.verseNumber,
                          ),
                          icon: const Icon(Icons.menu_book_rounded),
                          label: Text(
                            'Ouvrir le verset',
                            style: premiumText(
                              context,
                              15,
                              FontWeight.w700,
                              p.onPrimary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The definition, wearing the page background — l'écran entier *est* la
/// note — with its Bible references turned into tappable spans like the
/// reading screen's note references. Plain text without a destination to
/// offer. The size / typeface / alignment are the fiche-wide display
/// settings.
///
/// Stateful only to own the tap recognizers : recréés uniquement quand la
/// définition change — jamais à chaque build. Avant, `build` faisait
/// `_recognizers.add(...)` sans `clear`, donc la liste grossissait à chaque
/// reconstruction (et `FicheTextScope` reconstruit à chaque cran du curseur
/// de taille de texte) pour n'être vidée qu'au `dispose`. `build` reste pur
/// et ne relance plus `findNoteReferences` à chaque frame — le même correctif
/// que `dictionary_article_view`.
class _BymDefinition extends StatefulWidget {
  final String definition;
  final void Function(int bookIndex, int chapter, int verse)? onOpenVerse;
  final FicheTextStyle style;

  const _BymDefinition({
    required this.definition,
    required this.onOpenVerse,
    required this.style,
  });

  @override
  State<_BymDefinition> createState() => _BymDefinitionState();
}

class _BymDefinitionState extends State<_BymDefinition> {
  /// Recognizers owned by the linked reference spans, index-aligned with
  /// [_refs] : recréés uniquement dans [_syncLinks], disposés avant chaque
  /// recréation et avec le widget.
  final List<TapGestureRecognizer> _recognizers = [];
  List<TextReference> _refs = const [];

  @override
  void initState() {
    super.initState();
    _syncLinks();
  }

  @override
  void didUpdateWidget(covariant _BymDefinition old) {
    super.didUpdateWidget(old);
    if (widget.definition != old.definition ||
        !identical(widget.onOpenVerse, old.onOpenVerse)) {
      _syncLinks();
    }
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  /// Recalcule [_refs] et les recognizers, en disposant les anciens d'abord.
  /// Appelé depuis `initState` / `didUpdateWidget` uniquement : `build`
  /// reste pur.
  void _syncLinks() {
    _disposeRecognizers();
    if (widget.onOpenVerse == null) {
      _refs = const [];
      return;
    }
    final refs = findNoteReferences(widget.definition);
    final callback = widget.onOpenVerse!;
    for (final ref in refs) {
      final reference = ref.reference;
      _recognizers.add(
        TapGestureRecognizer()
          ..onTap = () => callback(
                reference.bookIndex,
                reference.chapter ?? 1,
                reference.verse ?? 1,
              ),
      );
    }
    _refs = refs;
  }

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    final readingTheme = BibleThemeScope.of(context);
    final size = widget.style.fontSize;
    if (_refs.isEmpty) {
      return Text(
        widget.definition,
        style: premiumText(
          context,
          size,
          FontWeight.w500,
          p.textDark,
          height: 1.6,
        ).copyWith(fontFamily: widget.style.fontFamily),
        textAlign: widget.style.align,
      );
    }
    final base = TextStyle(
      color: readingTheme.noteColor,
      fontSize: size,
      fontFamily: widget.style.fontFamily,
    );
    final linkStyle = TextStyle(
      color: readingTheme.linkColor,
      fontSize: size,
      fontFamily: widget.style.fontFamily,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dotted,
      backgroundColor: readingTheme.linkColor.withValues(alpha: .12),
    );
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (var i = 0; i < _refs.length; i++) {
      final ref = _refs[i];
      if (ref.start > cursor) {
        spans.add(
          TextSpan(text: widget.definition.substring(cursor, ref.start)),
        );
      }
      spans.add(
        TextSpan(
          text: widget.definition.substring(ref.start, ref.end),
          style: linkStyle,
          recognizer: _recognizers[i],
        ),
      );
      cursor = ref.end;
    }
    if (cursor < widget.definition.length) {
      spans.add(TextSpan(text: widget.definition.substring(cursor)));
    }
    return Text.rich(
      TextSpan(children: spans),
      style: base,
      textAlign: widget.style.align,
    );
  }
}
