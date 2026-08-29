import 'package:flutter/material.dart';

class LoadingSkeleton extends StatefulWidget {
  final Widget child;
  const LoadingSkeleton({super.key, required this.child});

  @override
  State<LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = Color.lerp(scheme.surface, scheme.onSurface, .09)!;
    final shine = Color.lerp(scheme.surface, scheme.onSurface, .025)!;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) {
          final travel = _controller.value * 2.8 - 1.4;
          return LinearGradient(
            begin: Alignment(travel - .8, 0),
            end: Alignment(travel + .8, 0),
            colors: [base, shine, base],
            stops: const [0.25, 0.5, 0.75],
          ).createShader(bounds);
        },
        child: child,
      ),
    );
  }
}

class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

/// Animated placeholder for the downloadable dictionary index
/// (`DictionaryBrowseScreen`): a search field, a row of letter chips, then the
/// article cards — the same skeleton across the whole screen instead of a bare
/// list under a half-built header.
class DictionaryBrowseLoadingSkeleton extends StatelessWidget {
  final int itemCount;

  const DictionaryBrowseLoadingSkeleton({super.key, this.itemCount = 6});

  @override
  Widget build(BuildContext context) {
    return LoadingSkeleton(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The search field.
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const SkeletonBox(width: 22, height: 22, radius: 6),
                const SizedBox(width: 10),
                const Expanded(
                  child: FractionallySizedBox(
                    widthFactor: .45,
                    alignment: Alignment.centerLeft,
                    child: SkeletonBox(height: 13, radius: 5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // The letter chips row.
          Row(
            children: [
              for (var i = 0; i < 5; i++) ...[
                SkeletonBox(width: i == 0 ? 68 : 44, height: 34, radius: 20),
                const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 16),
          // The article cards.
          Expanded(
            child: ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: itemCount,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) => Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(
                            width: index.isEven ? 140 : 104,
                            height: 15,
                            radius: 5,
                          ),
                          const SizedBox(height: 8),
                          const SkeletonBox(height: 10, radius: 5),
                          const SizedBox(height: 6),
                          const FractionallySizedBox(
                            widthFactor: .7,
                            alignment: Alignment.centerLeft,
                            child: SkeletonBox(height: 10, radius: 5),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const SkeletonBox(width: 22, height: 22, radius: 6),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated placeholder for the home page's async section (`HomeScreen`): the
/// « Reprendre la lecture » hero card and the studies list, shaped like the
/// real content so the arrival of the history does not cause a layout jump.
class HomeLoadingSkeleton extends StatelessWidget {
  final int studyCount;

  const HomeLoadingSkeleton({super.key, this.studyCount = 4});

  @override
  Widget build(BuildContext context) {
    return LoadingSkeleton(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The hero resume card.
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 78, height: 24, radius: 12),
                const SizedBox(height: 18),
                SkeletonBox(width: 240, height: 22, radius: 6),
                const SizedBox(height: 10),
                SkeletonBox(height: 14, radius: 5),
                const SizedBox(height: 7),
                SkeletonBox(width: 240, height: 14, radius: 5),
                const SizedBox(height: 22),
                const SkeletonBox(height: 8, radius: 4),
                const SizedBox(height: 22),
                Row(
                  children: [
                    SkeletonBox(width: 150, height: 15, radius: 5),
                    const Spacer(),
                    SkeletonBox(width: 46, height: 46, radius: 23),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          // The studies section header.
          Row(
            children: [
              SkeletonBox(width: 150, height: 18, radius: 5),
              const Spacer(),
              SkeletonBox(width: 62, height: 13, radius: 5),
            ],
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < studyCount; i++) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  SkeletonBox(width: 46, height: 46, radius: 16),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(
                          width: i.isEven ? 170 : 130,
                          height: 15,
                          radius: 5,
                        ),
                        const SizedBox(height: 6),
                        SkeletonBox(width: 110, height: 11, radius: 5),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SkeletonBox(width: 22, height: 22, radius: 6),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

/// Animated placeholder for screens whose final content is a list.
class ListLoadingSkeleton extends StatelessWidget {
  final int itemCount;
  final EdgeInsetsGeometry padding;

  const ListLoadingSkeleton({
    super.key,
    this.itemCount = 6,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) => LoadingSkeleton(
    child: ListView.separated(
      padding: padding,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            SkeletonBox(
              width: index.isEven ? 42 : 34,
              height: index.isEven ? 42 : 34,
              radius: 10,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(
                    width: index.isEven ? 150 : 112,
                    height: 13,
                    radius: 5,
                  ),
                  const SizedBox(height: 9),
                  const FractionallySizedBox(
                    widthFactor: .82,
                    alignment: Alignment.centerLeft,
                    child: SkeletonBox(height: 10, radius: 5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Animated placeholder for the reading surface itself ([ChapterReader], and
/// the panes of `ParallelReadingScreen`): the foldable book header when one
/// will actually appear (chapter 1 of a BYM-format version), then verse lines
/// with their leading numbers. Shaped so the arrival of the real chapter does
/// not jump the layout.
class ChapterLoadingSkeleton extends StatelessWidget {
  final bool header;
  final int verseCount;

  const ChapterLoadingSkeleton({
    super.key,
    this.header = true,
    this.verseCount = 14,
  });

  @override
  Widget build(BuildContext context) {
    return LoadingSkeleton(
      // Défilable-mais-figé, comme le squelette de l'Accueil : cette `Column`
      // est faite de hauteurs fixes (en-tête 122 px + 21 px par ligne de
      // verset), donc elle dépasse dès que le corps qui l'accueille descend
      // sous ce total — 9 px sur un 320x568, 217 px en paysage 360 px de haut.
      // Le rogner vaut mieux que le déborder, et le vrai chapitre qui arrive
      // est lui aussi défilable : rien ne saute.
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (header) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 160, height: 22, radius: 6),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Flexible(child: SkeletonBox(width: 70, height: 10, radius: 4)),
                        const SizedBox(width: 8),
                        Flexible(child: SkeletonBox(width: 50, height: 10, radius: 4)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        for (var i = 0; i < 2; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          const Expanded(
                            child: SkeletonBox(height: 28, radius: 8),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],
            for (var i = 0; i < verseCount; i++) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    const SkeletonBox(width: 24, height: 11, radius: 3),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: i.isEven ? .97 : .89,
                        child: const SkeletonBox(height: 11, radius: 4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Animated placeholder for a page of stacked cards ([ComparerScreen]): a
/// centred reference header, the selection chips, then the version cards.
class CardsLoadingSkeleton extends StatelessWidget {
  final int cardCount;

  const CardsLoadingSkeleton({super.key, this.cardCount = 3});

  @override
  Widget build(BuildContext context) {
    return LoadingSkeleton(
      // Même raison que [ChapterLoadingSkeleton] : hauteurs figées (en-tête,
      // pastilles, puis une carte par version) qui débordaient de 196 px en
      // paysage. La page réelle de `ComparerScreen` est elle aussi un
      // `SingleChildScrollView` avec la même marge de 20 : le squelette la
      // décalque donc exactement, sans saut à l'arrivée des versions.
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  SkeletonBox(width: 130, height: 24, radius: 6),
                  const SizedBox(height: 8),
                  SkeletonBox(width: 170, height: 10, radius: 4),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                for (var i = 0; i < 4; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  SkeletonBox(width: i.isEven ? 56 : 48, height: 32, radius: 20),
                ],
              ],
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < cardCount; i++) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SkeletonBox(width: 46, height: 18, radius: 6),
                        const SizedBox(width: 10),
                        Expanded(child: SkeletonBox(height: 12, radius: 4)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const SkeletonBox(height: 11, radius: 4),
                    const SizedBox(height: 6),
                    const FractionallySizedBox(
                      widthFactor: .72,
                      alignment: Alignment.centerLeft,
                      child: SkeletonBox(height: 11, radius: 4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
          ],
        ),
      ),
    );
  }
}

/// Brief first-mount placeholder shared by the shell destinations.
/// Detailed screens keep their own data skeletons after this gate.
class InterfaceLoadingGate extends StatefulWidget {
  final Widget child;
  final int variant;
  const InterfaceLoadingGate({
    super.key,
    required this.child,
    this.variant = 0,
  });

  @override
  State<InterfaceLoadingGate> createState() => _InterfaceLoadingGateState();
}

class _InterfaceLoadingGateState extends State<InterfaceLoadingGate> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.child;
    return _InterfaceSkeleton(variant: widget.variant);
  }
}

class _InterfaceSkeleton extends StatelessWidget {
  final int variant;
  const _InterfaceSkeleton({required this.variant});

  @override
  Widget build(BuildContext context) {
    // L'Accueil est le seul squelette de gate à hauteur *intrinsèque* : ses 659
    // px de boîtes figées (carte hero + 4 études) ne se rabotent pas comme les
    // `Expanded` des autres variantes. Rendu nu dans le corps borné du Scaffold,
    // il débordait dès que la hauteur utile passait sous ~660 px — 88 px sur un
    // 360x640, 160 px sur un 320x568, 299 px en paysage. Le mettre dans un
    // défilement (bloqué : le placeholder ne vit qu'une frame) rend la
    // contrainte verticale infinie, donc le débordement impossible.
    //
    // Le `SafeArea` et le padding 22/16 ne sont pas cosmétiques : ils sont ceux
    // de la `ListView` du vrai Accueil. Sans eux le squelette naissait bord à
    // bord puis sautait de 22 px vers l'intérieur à l'arrivée du contenu.
    if (variant == 0) {
      return const SafeArea(
        child: SingleChildScrollView(
          physics: NeverScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(22, 16, 22, 24),
          child: HomeLoadingSkeleton(),
        ),
      );
    }
    if (variant == 1) {
      return LoadingSkeleton(
        child: Padding(
          padding: EdgeInsets.fromLTRB(18, 20, 18, 18),
          child: Column(
            children: [
              // 150 + 10 + 90 + 42 = 292 px de largeur figée, pour 284 px
              // disponibles sur un écran de 320 : le squelette débordait de
              // 8 px. Le groupe de gauche passe dans un `Expanded` (qui garde
              // le rond collé au bord droit, comme le faisait la `Spacer`) et
              // ses deux boîtes deviennent `Flexible` dans leur rapport 5/3 :
              // tailles nominales intactes dès ~360 px, rabotées
              // proportionnellement en dessous.
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          flex: 5,
                          child: SkeletonBox(width: 150, height: 44, radius: 12),
                        ),
                        SizedBox(width: 10),
                        Flexible(
                          flex: 3,
                          child: SkeletonBox(width: 90, height: 44, radius: 12),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 10),
                  SkeletonBox(width: 42, height: 42, radius: 21),
                ],
              ),
              SizedBox(height: 18),
              Expanded(
                child: ListLoadingSkeleton(
                  itemCount: 8,
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return LoadingSkeleton(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: variant == 2 ? 220 : 180, height: 24, radius: 7),
            SizedBox(height: 18),
            SkeletonBox(height: 52, radius: 14),
            SizedBox(height: 18),
            Expanded(
              child: ListLoadingSkeleton(
                itemCount: variant == 3 ? 6 : 7,
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
