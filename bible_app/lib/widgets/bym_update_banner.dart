import 'package:flutter/material.dart';

import '../data/bym_update_service.dart';
import 'premium_style.dart';

/// Bandeau défilant annonçant qu'une correction du texte BYM attend l'accord du
/// lecteur : « Mettre à jour le texte BYM dans les Réglages · 21 livres ».
///
/// Troisième surface d'annonce, avec la pastille de la Bibliothèque et la section
/// de Réglages. Toutes trois écoutent [BymUpdateChecker.available], donc elles ne
/// peuvent pas se contredire, et **aucune n'installe quoi que ce soit** : celle-ci
/// conduit à Réglages, seul endroit qui décide d'un téléchargement. Elle existe
/// parce que les deux autres se laissent manquer — la lecture est l'écran où le
/// lecteur passe son temps.
///
/// Elle disparaît d'elle-même : `BymUpdateChecker.clear()` remet [available] à
/// null dès que la mise à jour est installée, ou que le lecteur revient au texte
/// embarqué.
///
/// **Rien à l'écran** sans mise à jour disponible — pas un `SizedBox` de quelques
/// pixels, rien. C'est ce qui garantit qu'aucune animation ne tourne dans le cas
/// ordinaire, donc que les tests widget des écrans hôtes continuent de se
/// stabiliser : un défilement en boucle programme des frames sans fin et
/// `pumpAndSettle` attendrait pour toujours. Un test **de ce bandeau** doit donc
/// pomper des durées explicites, jamais `pumpAndSettle` — sauf dans les deux cas
/// où l'on vérifie précisément que rien ne bouge (aucune mise à jour, ou
/// « réduire les animations »).
///
/// Le défilement a lieu sur **toutes** les largeurs, téléphone comme tablette :
/// c'est le mouvement qui fait remarquer l'annonce, et une tablette où la phrase
/// tient en entier n'a pas moins besoin d'être vue. Seule l'option système
/// « réduire les animations » l'arrête (voir [_MarqueeText]).
class BymUpdateBanner extends StatelessWidget {
  /// Conduit à la section « MISE À JOUR DU TEXTE » de Réglages.
  ///
  /// Null quand l'écran hôte n'a pas de route vers Réglages (lecteur isolé,
  /// tests) : le bandeau reste alors une annonce à lire, il ne devient pas un
  /// faux bouton inerte — la phrase dit déjà où aller.
  final VoidCallback? onOpenSettings;

  const BymUpdateBanner({super.key, this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BymUpdateCheck?>(
      valueListenable: BymUpdateChecker.available,
      builder: (context, check, _) {
        if (check == null || !check.hasUpdate) return const SizedBox.shrink();
        return _Banner(
          // Le compte vient du plan lui-même : c'est le même nombre que la
          // pastille de la Bibliothèque et que le bouton de Réglages.
          label: 'Mettre à jour le texte BYM dans les Réglages '
              '· ${check.bookLabel}',
          onTap: onOpenSettings,
        );
      },
    );
  }
}

/// La bande elle-même : liseré d'accent, icône, texte défilant, chevron.
class _Banner extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _Banner({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Material(
      color: p.primarySoft,
      child: InkWell(
        key: const Key('bymUpdateBanner'),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: p.primary.withValues(alpha: .28)),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, size: 14, color: p.primary),
              const SizedBox(width: 8),
              // Le texte défile dans la place qui reste : icône et chevron sont
              // posés en premier, donc ils ne se font jamais rogner par une
              // phrase longue ou une police agrandie.
              Expanded(
                child: _MarqueeText(
                  text: label,
                  style: premiumText(context, 12.5, FontWeight.w700, p.primary),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, size: 16, color: p.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Une ligne de texte qui défile de droite à gauche, sans fin.
///
/// Sur toutes les largeurs : c'est le mouvement qui attrape l'œil, et une
/// tablette où la phrase tient en entier n'a pas moins besoin qu'on la remarque.
/// Seule l'option système « réduire les animations » l'arrête — là, le
/// défilement perpétuel est précisément ce qu'on demande d'éviter, et la phrase
/// reste lisible, tronquée.
///
/// Deux copies séparées d'un intervalle défilent ensemble sur la largeur d'une
/// copie plus l'intervalle, puis l'animation reprend à zéro : à cet instant la
/// seconde copie occupe exactement la place de la première, donc la boucle est
/// invisible. C'est ce qui impose de **mesurer** le texte ([TextPainter]) au lieu
/// de le laisser se dimensionner tout seul : la translation et la période en
/// dépendent.
///
/// La vitesse est en pixels par seconde, pas une durée fixe : une phrase deux
/// fois plus longue défile deux fois plus longtemps, au même rythme de lecture.
class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;

  /// Blanc entre la fin d'une copie et le début de la suivante.
  static const double gap = 56;

  /// Vitesse du défilement. Réglages, pas paramètres : un seul bandeau les
  /// utilise, et un défilement qui change de rythme d'un endroit à l'autre de
  /// l'application se remarquerait comme un défaut.
  static const double pixelsPerSecond = 42;

  const _MarqueeText({
    required this.text,
    required this.style,
  });

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    // Remplacée par [_syncTicker] avant le premier tour : `repeat(period:)` fixe
    // la vraie période, celle que la largeur mesurée commande.
    duration: const Duration(seconds: 1),
  );

  /// Largeur d'**une** copie, dans le style et l'échelle de texte en vigueur.
  double _textWidth = 0;

  /// Hauteur de cette même copie. Mesurée, et pas déduite du style : c'est elle
  /// qui borne le défilement. Sans elle, `OverflowBox` lève « was given an
  /// infinite size during layout » — le bandeau vit dans une `Column`, qui
  /// n'impose aucune hauteur, et la `Row` la relaie telle quelle.
  double _textHeight = 0;

  /// Accessibilité : « réduire les animations » coupe le défilement.
  bool _reducedMotion = false;

  /// Période en cours, pour ne pas relancer un défilement qui tourne déjà :
  /// `repeat` repartirait de zéro, et le saut se verrait.
  Duration? _running;

  /// La largeur offerte n'entre pas dans cette décision : on défile aussi quand
  /// la phrase tient. Seul le réglage d'accessibilité l'emporte.
  bool get _shouldScroll => !_reducedMotion && _textWidth > 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ici et pas dans `initState` : la mesure a besoin de l'échelle de texte
    // ambiante (`ResponsiveTextScaling` en pose une), qui est une dépendance
    // héritée — un changement de taille système repasse donc par ici.
    _measure();
  }

  @override
  void didUpdateWidget(_MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _measure();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _measure() {
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      textDirection: Directionality.of(context),
      maxLines: 1,
      // La même échelle que celle avec laquelle `Text` peindra : sans elle, la
      // largeur mesurée dérive de la largeur réelle dès que le lecteur grossit
      // la police, et la reprise de boucle se voit.
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    _textWidth = painter.width;
    _textHeight = painter.height;
    painter.dispose();

    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    _syncTicker();
  }

  /// Aligne le ticker sur ce que la mesure commande : il tourne dès qu'il y a un
  /// texte, il est à l'arrêt si le lecteur a demandé moins d'animations.
  void _syncTicker() {
    if (!_shouldScroll) {
      // Un défilement perpétuel qu'on ne peut pas arrêter est exactement ce que
      // « réduire les animations » demande d'éviter. La phrase reste lisible.
      //
      // `stop()` seul, sans remise à zéro de la valeur : écrire `value`
      // préviendrait les auditeurs, or on arrive ici depuis
      // `didChangeDependencies`, donc en pleine construction d'arbre. De toute
      // façon `repeat()` repart de la borne basse s'il faut redéfiler un jour.
      _controller.stop();
      _running = null;
      return;
    }
    final period = Duration(
      milliseconds:
          ((_textWidth + _MarqueeText.gap) /
                  _MarqueeText.pixelsPerSecond *
                  1000)
              .round()
              .clamp(1200, 60000),
    );
    if (_controller.isAnimating && period == _running) return;
    _running = period;
    _controller.repeat(period: period);
  }

  @override
  Widget build(BuildContext context) {
    // Plus de `LayoutBuilder` : la largeur offerte n'entre plus dans la
    // décision, et la translation ne dépend que du texte mesuré. Un `ClipRect`
    // borné par l'`Expanded` parent suffit à couper ce qui dépasse.
    if (!_shouldScroll) {
      return Text(
        widget.text,
        style: widget.style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    final copy = Text(
      widget.text,
      style: widget.style,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.clip,
    );
    final span = _textWidth + _MarqueeText.gap;
    return SizedBox(
      height: _textHeight,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Transform.translate(
            key: const Key('bymUpdateMarquee'),
            offset: Offset(-_controller.value * span, 0),
            // `OverflowBox` relâche la contrainte de largeur : les deux copies
            // dépassent à droite au lieu d'être comprimées, et le `ClipRect`
            // au-dessus les coupe au bord du bandeau.
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              maxWidth: double.infinity,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  copy,
                  const SizedBox(width: _MarqueeText.gap),
                  copy,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
