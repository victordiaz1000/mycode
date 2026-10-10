import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/book_catalog.dart';
import 'package:bible_app/data/library_store.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/data/version_catalog.dart';
import 'package:bible_app/data/version_repository.dart';

import 'support/fake_bible_bundle.dart';

/// A book exactly as getbible serves it, mixed types included: `chapter` is an
/// int on the chapter but a String on the verse.
Map<String, dynamic> getbibleBook(int standardNumber, {int chapters = 2}) => {
      'translation': 'Darby',
      'abbreviation': 'darby',
      'lang': 'fr',
      'nr': standardNumber,
      // English on purpose: the KJV answers in its own language.
      'name': 'Book $standardNumber',
      'chapters': [
        for (var c = chapters; c >= 1; c--)
          {
            'chapter': c,
            'name': 'Book $standardNumber $c',
            'verses': [
              for (var v = 1; v <= 3; v++)
                {
                  'chapter': '$c',
                  'verse': '$v',
                  'name': 'Book $standardNumber $c:$v',
                  'text': 'Texte téléchargé $c:$v.',
                },
            ],
          },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late LibraryStore store;
  late VersionRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('bym_version_repo_test');
    LibraryStore.useRoot(temp);
    LocalRepository.useBundle(FakeBibleBundle());
    VersionRepository.clearCache();
    store = LibraryStore();
    repository = VersionRepository(store: store);
  });

  tearDown(() async {
    LibraryStore.useAppDirectory();
    LocalRepository.useRootBundle();
    VersionRepository.clearCache();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  group('bookFromGetbible', () {
    test('keeps the French BYM name, not the translation\'s own', () {
      final book = bookFromGetbible(getbibleBook(19), bymIndex: 27);
      // BYM 27 is Psaumes; getbible answered « Book 19 ».
      expect(book.book, catalogEntry(27).shortName);
      expect(book.abbreviation, catalogEntry(27).abbreviation);
      expect(book.number, 27);
    });

    test('sorts the chapters and numbers the verses', () {
      final book = bookFromGetbible(getbibleBook(1, chapters: 3), bymIndex: 1);

      expect(book.chapters.map((c) => c.chapter), [1, 2, 3]);
      final verse = book.chapters[1].verses.last;
      expect(verse.verse, '2:3');
      expect(verse.number, 3);
      expect(verse.text, 'Texte téléchargé 2:3.');
      // No BYM notes in a downloaded translation — the plain text stands in.
      expect(verse.textWithNotes, verse.text);
      expect(verse.notes, isEmpty);
      expect(verse.section, isNull);
    });

    test('survives a malformed payload instead of throwing', () {
      final book = bookFromGetbible({
        'chapters': [
          'not a chapter',
          {
            'chapter': '4',
            'verses': [
              'not a verse',
              {'verse': 2, 'text': '  Espaces autour.  '},
              {'verse': 3, 'text': '   '},
            ],
          },
        ],
      }, bymIndex: 1);

      expect(book.chapters, hasLength(1));
      expect(book.chapters.single.chapter, 4, reason: 'String chapter number');
      // The blank verse is dropped; the other keeps its trimmed text.
      expect(book.chapters.single.verses, hasLength(1));
      expect(book.chapters.single.verses.single.verse, '4:2');
      expect(book.chapters.single.verses.single.text, 'Espaces autour.');
    });
  });

  group('VersionRepository', () {
    test('BYM comes from the embedded bundle', () async {
      final book = await repository.loadBook('BYM', 1);
      expect(book.chapters, hasLength(2));
      expect(book.chapters.first.verses.first.notes, isNotEmpty);
      expect(repository.isEmbedded('BYM'), isTrue);
    });

    test('LSGS is treated as an embedded Strong version', () async {
      final book = await repository.loadBook('LSGS', 1);
      expect(book.book, 'Genèse');
      expect(book.chapters, isNotEmpty);
      expect(repository.isEmbedded('LSGS'), isTrue);
      expect(book.chapters.first.verses.first.text, contains('H0430'));
      expect(book.chapters.first.verses.first.text, contains('Dieu H0430'));
      expect(book.chapters.first.verses.first.text, contains('H0430 créa'));
    });

    test('LSS reads as its own embedded version, not as the LSGS', () async {
      final lss = await repository.loadBook('LSS', 1);
      expect(lss.book, 'Genèse');
      expect(lss.chapters, isNotEmpty);
      expect(repository.isEmbedded('LSS'), isTrue,
          reason: 'une version embarquée est toujours lisible, registre ouvert '
              'ou non');

      // Le texte de l'étude devient un texte de lecture : mêmes codes en ligne,
      // « Dieu H0430 », cliquables dans la tuile.
      final verse = lss.chapters.first.verses.first.text;
      expect(verse, contains('Dieu H0430'));

      // Ce qui distingue les deux corpus, c'est la densité des ancres : la LSS
      // numérote le waw consécutif de Genèse 1:1, que la LSGS ignore. Si
      // `loadBook('LSS')` servait le mauvais dossier, les deux textes seraient
      // identiques et ce jeton n'y serait pas.
      expect(verse, contains('H8804'));
      final lsgs = await repository.loadBook('LSGS', 1);
      expect(lsgs.chapters.first.verses.first.text, isNot(contains('H8804')));
      expect(verse, isNot(equals(lsgs.chapters.first.verses.first.text)));
    });

    test('a downloaded version comes from the device', () async {
      await store.saveBook('DBY', 1, getbibleBook(1));

      final book = await repository.loadBook('DBY', 1);
      expect(book.chapters.first.verses.first.text, 'Texte téléchargé 1:1.');

      final chapter = await repository.loadChapter('DBY', 1, 2);
      expect(chapter.verses, hasLength(3));
      expect(await repository.chapterCount('DBY', 1), 2);
    });

    test('a book that was never downloaded is refused, not faked', () async {
      // Falling back to the BYM text under a « DBY » label would be a silent
      // lie: the reader has no way to notice.
      expect(
        () => repository.loadBook('DBY', 5),
        throwsA(isA<BookNotDownloaded>()
            .having((e) => e.bymIndex, 'bymIndex', 5)
            .having((e) => e.message, 'message', contains('DBY'))),
      );
    });

    test('an unknown version code is treated as not downloaded', () async {
      expect(() => repository.loadBook('ZZZ', 1),
          throwsA(isA<BookNotDownloaded>()));
    });

    test('the parsed book is cached, and forgotten on demand', () async {
      await store.saveBook('DBY', 1, getbibleBook(1));
      final first = await repository.loadBook('DBY', 1);
      expect(identical(await repository.loadBook('DBY', 1), first), isTrue);

      // The Bibliothèque deleting a version must not leave it readable.
      await store.remove('DBY');
      VersionRepository.forget('DBY');
      expect(() => repository.loadBook('DBY', 1),
          throwsA(isA<BookNotDownloaded>()));
    });

    test('neighbouring chapters follow the BYM order whatever the version',
        () async {
      // Nothing is downloaded for DBY, yet the arrows must still resolve:
      // chapter counts are a property of the canon, not of the translation.
      expect(await repository.previousChapter(1, 1), isNull);
      expect(await repository.nextChapter(1, 1), (1, 2));
      expect(await repository.nextChapter(1, 2), (2, 1));
      expect(await repository.previousChapter(2, 1), (1, 2));
    });
  });

  group('tokensFor', () {
    test('serves the LSS corpus, whose anchors go further than the LSGS',
        () async {
      final lss =
          await repository.tokensFor(VersionRepository.lssCode, 1, 1, 1);
      expect(lss, isNotEmpty);

      // Genèse 1.1 en LSS porte des particules sans mot français — H8804, le
      // waw consécutif, et H0853, le marqueur d'accusatif — que la LSGS ne
      // numérote pas : c'est tout l'objet de ce corpus.
      final sansMot = lss
          .where((t) => (t.strong ?? '').isNotEmpty && t.text.trim().isEmpty)
          .map((t) => t.strong)
          .toList();
      expect(sansMot, contains('H8804'));
      expect(sansMot, contains('H0853'));

      final lsgs =
          await repository.tokensFor(VersionRepository.lsgsCode, 1, 1, 1);
      expect(
        lsgs
            .where((t) => (t.strong ?? '').isNotEmpty && t.text.trim().isEmpty)
            .toList(),
        isEmpty,
        reason: 'la LSGS embarquée n\'a aucun jeton sans texte',
      );
    });

    test('any code but the LSS answers the LSGS', () async {
      final lsgs =
          await repository.tokensFor(VersionRepository.lsgsCode, 1, 1, 1);
      final autre = await repository.tokensFor('ZZZ', 1, 1, 1);
      expect(
        autre.map((t) => t.text).join(),
        lsgs.map((t) => t.text).join(),
      );
    });

    test('the verses LSS lacks at the source fall back to the LSGS', () async {
      // Le marqueur de verset manque dans la source : Ex 28.42 et Nb 25.19
      // existent en LSGS, et le lexique doit pouvoir s'ouvrir dessus.
      for (final (book, chapter, verse) in [(2, 28, 42), (4, 25, 19)]) {
        final tokens = await repository.tokensFor(
            VersionRepository.lssCode, book, chapter, verse);
        expect(tokens, isNotEmpty,
            reason: 'le lexique doit s\'ouvrir sur $book $chapter:$verse');
      }

      // Ac 19.41 : ni LSS ni LSGS n'y porte un seul jeton — ni erreur, ni
      // prétention d'un verset que le corpus n'a pas.
      expect(
        await repository.tokensFor(VersionRepository.lssCode, 44, 19, 41),
        isEmpty,
      );
    });
  });

  group('the format of a version', () {
    test('only the BYM schema is said to carry notes', () {
      expect(versionByCode('BYM')!.carriesNotes, isTrue);
      // What the reader keys « Texte + notes » and the book header on. getbible
      // serves text alone, so claiming notes here would show an empty toggle.
      expect(versionByCode('DBY')!.carriesNotes, isFalse);
      expect(versionByCode('LSG')!.carriesNotes, isFalse);
      expect(versionByCode('LSGS')!.carriesNotes, isFalse,
          reason: 'LSGS gives Strong tokens but no BYM metadata or introduction');
    });

    test('everything downloadable has its own parser and a named source', () {
      // The flag is not free-standing: `loadBook` chooses its parser from it, so
      // a downloadable entry left on the wrong format would parse to an empty
      // book at the first download rather than fail loudly. Three schemas are
      // legal — getbible for the bare corpus, SEF for the Septuagint's Greek +
      // French, ATI for the word-by-word interlinear, which `bookFromAti`
      // flattens to a line of French glosses. What a downloadable entry can
      // never claim is the BYM schema, whose metadata its files do not carry.
      //
      // The list is enumerated rather than written « anything but bym » on
      // purpose: a fourth format must be added here deliberately, once someone
      // has checked that `loadBook` has an arm for it.
      const servables = {
        VersionFormat.getbible,
        VersionFormat.sef,
        VersionFormat.ati,
      };
      final downloadable = [
        for (final group in versionCatalog)
          for (final version in group.versions)
            if (version.downloadable) version,
      ];
      expect(downloadable, isNotEmpty);
      for (final version in downloadable) {
        expect(
          servables.contains(version.format),
          isTrue,
          reason: '${version.code} must name a parser `loadBook` can reach',
        );
        expect(version.fetchable, isTrue, reason: version.code);
        expect(version.getbibleId != null || version.urlTemplate != null, isTrue,
            reason: '${version.code} must name a source');
      }
    });

    test('the two HTML corpora keep their host and their copyright', () {
      // CHO and KJF come from the same archives (`CHO.zip`, `KJF.zip`) and the
      // same converter (`appCodebar/html_verses_to_json.py`), served like OST
      // and NCL: one JSON per book on the GitHub host, standard numbering.
      // The copyright line is the condition on which a text under rights is
      // published at all — it is asserted, not hoped for.
      for (final code in ['CHO', 'KJF']) {
        final version = versionByCode(code)!;
        expect(version.availability, VersionAvailability.downloadable,
            reason: '$code must be offerable in the Bibliothèque');
        expect(version.fetchable, isTrue, reason: code);
        expect(
          version.urlTemplate,
          'https://raw.githubusercontent.com/victordiaz1000/-bym-bibles/main/'
          '${code == 'CHO' ? 'chouraqui' : 'kjf'}/{book}.json',
        );
        expect(version.rights, contains('©'), reason: '$code names its author');
      }
      expect(versionByCode('CHO')!.rights, contains('Desclée de Brouwer'));
      expect(versionByCode('KJF')!.rights, contains('Stratford'));
      // Both are French, and neither carries notes or Strong: getbible schema.
      for (final code in ['CHO', 'KJF']) {
        final version = versionByCode(code)!;
        expect(version.languageCode, 'FR', reason: code);
        expect(version.carriesNotes, isFalse, reason: code);
        expect(version.hasStrong, isFalse, reason: code);
      }
    });

    test('an unknown code falls on the poorer schema', () {
      // The default matters: a code absent from the catalogue must not be read
      // as BYM-format, which would look for metadata that is not there.
      expect(versionByCode('ZZZ'), isNull);
      expect(const VersionEntry(code: 'ZZZ', name: 'z', rights: 'z').format,
          VersionFormat.getbible);
    });
  });

  group('the SEF Septuagint', () {
    test('is an Old Testament-only downloadable on the GitHub host', () {
      final sef = versionByCode('SEF')!;
      expect(sef.availability, VersionAvailability.downloadable);
      expect(sef.fetchable, isTrue);
      expect(sef.format, VersionFormat.sef);
      expect(sef.carriesNotes, isFalse);
      expect(sef.otOnly, isTrue);
      expect(sef.bookCount, 39);
      expect(sef.containsBook(39), isTrue, reason: 'Malachie');
      expect(sef.containsBook(40), isFalse, reason: 'Matthieu n\'existe pas');
      expect(
        sef.urlTemplate,
        'https://raw.githubusercontent.com/victordiaz1000/-bym-bibles/'
        'main/sef/{book}.json',
      );
      // The copyright of a text under rights is asserted on the card, not
      // hoped for — same rule as CHO and KJF.
      expect(sef.rights, contains('©'));
      expect(sef.rights, contains('Deutsche Bibelgesellschaft'));
      // Les deux traducteurs, nommés par la source elle-même (introductions
      // du corpus) : la Bibliothèque les affiche sous le copyright.
      expect(sef.attribution, contains('Pierre Giguet'));
      expect(sef.attribution, contains('Marguerite Harl'));
      expect(sef.languageCode, 'FR');
    });

    test('a New Testament book is absent from the version, not missing', () async {
      // Nothing is downloaded for SEF: the canon check must answer before the
      // device, or Matthieu would read as « téléchargez-le » — and every book
      // past Malachie would 404 during the install.
      expect(
        () => repository.loadBook('SEF', 40),
        throwsA(isA<BookNotInVersion>()
            .having((e) => e.code, 'code', 'SEF')
            .having((e) => e.bymIndex, 'bymIndex', 40)
            .having((e) => e.message, 'message', contains('Ancien Testament'))),
      );
      // Still a BookNotDownloaded for every screen that already handles one.
      expect(() => repository.loadBook('SEF', 40),
          throwsA(isA<BookNotDownloaded>()));
    });

    test('parses grec, alexandrie and section, keeping a Greek-only verse', () {
      final book = bookFromSef({
        'chapters': [
          {
            'chapter': 1,
            'verses': [
              {
                'chapter': '1',
                'verse': '1',
                'text': 'Au commencement…',
                'grec': 'Ἐν ἀρχῇ…',
                'alexandrie': 'Au commencement, Dieu fit…',
                // Les pieds de page voyagent dans le fichier : le parseur ne
                // doit en faire ni une note ancrée ni quoi que ce soit d'autre.
                'notes': ['Pied de page resté en données'],
                'section': 'Le décalogue',
              },
              {'chapter': '1', 'verse': '2', 'grec': 'Καὶ ἡ γῆ…'},
              {'chapter': '1', 'verse': '3', 'text': '   ', 'grec': '  '},
            ],
          },
        ],
      }, bymIndex: 1);

      final verses = book.chapters.single.verses;
      expect(verses, hasLength(2), reason: 'the double-empty verse is dropped');
      expect(verses[0].text, 'Au commencement…');
      expect(verses[0].grec, 'Ἐν ἀρχῇ…');
      expect(verses[0].alexandrie, 'Au commencement, Dieu fit…');
      expect(verses[0].section, 'Le décalogue');
      expect(verses[0].textWithNotes, verses[0].text);
      expect(verses[0].notes, isEmpty,
          reason: 'SEF footnotes stay in the file, unanchored and unread');
      expect(verses[1].text, '', reason: 'a French hole keeps its Greek line');
      expect(verses[1].alexandrie, isNull);
    });
  });
}
