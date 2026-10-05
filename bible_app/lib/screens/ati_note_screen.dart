import 'package:flutter/material.dart';

import '../data/ati_note_html.dart';
import '../data/ati_notes.dart';
import '../widgets/ati_note_view.dart';
import '../widgets/fiche_text_settings.dart';
import '../widgets/premium_style.dart';

/// Une page du glossaire de l'interlinéaire, ouverte à part : c'est ce que
/// le renvoi d'un mot (`n12`, `d12`, `r2`, `abr`) promet en étant touché.
///
/// La page porte ses propres liens et les rend tels quels : un code Strong y
/// ouvre la fiche du lexique, un renvoi vers une autre page y pousse cette
/// page-ci — la pile s'empile comme pour les articles de dictionnaire, et le
/// retour en arrière suit.
class AtiNoteScreen extends StatefulWidget {
  const AtiNoteScreen({
    super.key,
    required this.noteId,
    this.onStrongTap,
    this.onVerseTap,
  });

  /// L'identifiant du renvoi : la clé dans `notes.json`.
  final String noteId;

  /// Ouvre la fiche Strong d'un code — fourni par celui qui a poussé la page,
  /// qui a déjà la machinerie d'occurrences sous la main.
  final Future<void> Function(String strong)? onStrongTap;

  /// Ouvre un verset de la LSGS, en code OSIS (`GEN1.2`). Non fourni : les
  /// références de la source se lisent, elles ne se pressent pas.
  final Future<void> Function(String osis)? onVerseTap;

  /// Pousse une page du glossaire : le seul endroit qui sache relier les
  /// callbacks, pour que le lecteur n'ait qu'un nom de page à donner.
  static Future<void> push(
    BuildContext context,
    String noteId, {
    Future<void> Function(String strong)? onStrongTap,
    Future<void> Function(String osis)? onVerseTap,
  }) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => AtiNoteScreen(
        noteId: noteId,
        onStrongTap: onStrongTap,
        onVerseTap: onVerseTap,
      ),
    ),
  );

  @override
  State<AtiNoteScreen> createState() => _AtiNoteScreenState();
}

class _AtiNoteScreenState extends State<AtiNoteScreen> {
  AtiNote? _note;
  AtiNoteDocument? _document;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final note = await AtiNotes.instance.lookup(widget.noteId);
    if (!mounted) return;
    setState(() {
      _note = note;
      // Le démontage ne jette jamais : une page illisible s'affiche vide,
      // sous son titre, plutôt que de faire tomber l'écran.
      _document = note == null ? null : AtiNoteDocument.parse(note.html);
      _loading = false;
    });
  }

  /// Un renvoi du glossaire vers une autre page : résolu par son intitulé,
  /// celui que la source met dans `g.php?…&g=…`.
  Future<void> _openPage(String pageName) async {
    final page = await AtiNotes.instance.lookupByName(pageName);
    if (!mounted) return;
    if (page == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Page « $pageName » absente du glossaire'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    await AtiNoteScreen.push(
      context,
      page.id,
      onStrongTap: widget.onStrongTap,
      onVerseTap: widget.onVerseTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FicheTextScope(
      group: DisplayGroup.fiches,
      builder: (context, style) => _buildScaffold(context, style),
    );
  }

  Widget _buildScaffold(BuildContext context, FicheTextStyle style) {
    final p = premiumPalette(context);
    return Scaffold(
      backgroundColor: premiumBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: p.textDark,
        centerTitle: true,
        title: Text(
          _loading ? 'Glossaire' : _note?.name ?? 'Page introuvable',
          style: premiumText(context, 16, FontWeight.w800, p.textDark),
        ),
        actions: const [FicheDisplayMenuButton(group: DisplayGroup.fiches)],
      ),
      body: SafeArea(top: false, child: _body(context, style, p)),
    );
  }

  Widget _body(BuildContext context, FicheTextStyle style, PremiumPalette p) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final note = _note;
    if (note == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'La page « ${widget.noteId} » n’existe pas dans le glossaire.',
            textAlign: TextAlign.center,
            style: premiumText(context, 15, FontWeight.w500, p.textGrey),
          ),
        ),
      );
    }
    final document = _document!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
        decoration: premiumSurface(context, depth: 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (document.isEmpty)
              // Sans corps, la page vaut au moins son titre de source.
              Text(
                note.title,
                style: premiumText(context, 17, FontWeight.w700, p.textDark),
              )
            else
              AtiNoteView(
                document: document,
                fontSize: style.fontSize,
                fontFamily: style.fontFamily,
                onStrongTap: widget.onStrongTap == null
                    ? null
                    : (strong) => widget.onStrongTap!(strong),
                onPageTap: _openPage,
                onVerseTap: widget.onVerseTap == null
                    ? null
                    : (osis) => widget.onVerseTap!(osis),
              ),
            const SizedBox(height: 18),
            // La mention de la source, à l'endroit où la page la ferme.
            Text(
              '© Biblia Universalis · texte hébreu : '
              'Biblia Hebraica Stuttgartensia',
              style: premiumText(context, 11, FontWeight.w500, p.textGrey),
            ),
          ],
        ),
      ),
    );
  }
}
