// Tests de la logique métier et de l'affichage, sans dépendance réseau.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:khoutba/ecrans/accueil.dart';
import 'package:khoutba/enregistreur.dart';
import 'package:khoutba/extraction_audio.dart';
import 'package:khoutba/fournisseurs.dart';
import 'package:khoutba/import_media.dart';
import 'package:khoutba/modeles.dart';
import 'package:khoutba/theme.dart';
import 'package:khoutba/traitement.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => initializeDateFormatting('fr_FR', null));

  group('Choix du modèle Gemini', () {
    // Liste volontairement bruitée, telle que la renvoie l'API.
    const brut = [
      ModeleGemini('embedding-001', 'Embedding'),
      ModeleGemini('imagen-4.0-generate', 'Imagen 4'),
      ModeleGemini('gemini-2.0-flash-live-001', 'Live'),
      ModeleGemini('gemini-3-pro-preview', 'Pro preview'),
      ModeleGemini('gemini-3-flash', 'Flash 3'),
      ModeleGemini('gemini-3-flash-lite', 'Flash Lite'),
      ModeleGemini('gemini-flash-latest', 'Flash latest'),
    ];

    test('écarte les modèles inadaptés (images, embeddings, live)', () {
      final ids = classerModelesGemini(brut).map((m) => m.id);
      expect(ids, isNot(contains('embedding-001')));
      expect(ids, isNot(contains('imagen-4.0-generate')));
      expect(ids, isNot(contains('gemini-2.0-flash-live-001')));
    });

    test('retient un flash récent en premier choix', () {
      expect(classerModelesGemini(brut).first.id, 'gemini-3-flash');
    });

    test('déclasse les versions preview et lite', () {
      final ids = classerModelesGemini(brut).map((m) => m.id).toList();
      expect(ids.indexOf('gemini-3-flash'), lessThan(ids.indexOf('gemini-3-pro-preview')));
      expect(ids.indexOf('gemini-3-flash'), lessThan(ids.indexOf('gemini-3-flash-lite')));
    });

    test('liste vide reste vide (pas de plantage)', () {
      expect(classerModelesGemini(const []), isEmpty);
    });
  });

  group('Lecture des réponses du modèle', () {
    test('accepte un JSON entouré de ```json', () {
      expect(parseJsonSouple('```json\n{"titre":"Test"}\n```')['titre'], 'Test');
    });

    test('accepte du texte autour du JSON', () {
      expect(parseJsonSouple('Voici : {"titre":"Gratitude"} — voilà.')['titre'], 'Gratitude');
    });

    test('refuse une réponse sans JSON', () {
      expect(() => parseJsonSouple('désolé, je ne peux pas'), throwsA(isA<ErreurIA>()));
    });

    test('synthèse complète relue depuis le JSON', () {
      final s = Synthese.depuisJson(parseJsonSouple('''
        {"titre":"T","theme":"Th","resume":"R",
         "points_cles":["a","b"],
         "citations":[{"type":"coran","texte_arabe":"نص","traduction":"tr","reference":"2:1"}],
         "conseils":["c"],"douas":[]}'''));
      expect(s.pointsCles.length, 2);
      expect(s.citations.single.reference, '2:1');
      expect(s.douas, isEmpty);
    });

    test('champs manquants tolérés', () {
      final s = Synthese.depuisJson(parseJsonSouple('{"titre":"T"}'));
      expect(s.pointsCles, isEmpty);
      expect(s.citations, isEmpty);
    });
  });

  group('Enregistrement', () {
    Enregistrement fabriquer() => Enregistrement(
          id: 'abc',
          titre: 'Khoutba test',
          creeLe: DateTime(2026, 7, 24, 13, 5),
          cheminAudio: '/tmp/abc.m4a',
          dureeSecondes: 1830,
        );

    test('aller-retour JSON sans perte', () {
      final rec = fabriquer()
        ..transcription = 'نص'
        ..traduction = 'texte'
        ..statut = Statut.termine;
      final relu = Enregistrement.depuisJson(rec.versJson());
      expect(relu.id, rec.id);
      expect(relu.transcription, 'نص');
      expect(relu.statut, Statut.termine);
      expect(relu.dureeSecondes, 1830);
    });

    test('un statut interrompu revient à un état stable', () {
      final rec = fabriquer()..statut = Statut.traduction;
      expect(rec.statutStable, Statut.transcrit); // rien de traduit encore
      rec.traduction = 'déjà traduit';
      expect(rec.statutStable, Statut.traduit);
      rec.statut = Statut.synthese;
      expect(rec.statutStable, Statut.traduit);
    });
  });

  group('Affichage', () {
    test('durées formatées lisiblement', () {
      expect(formaterDuree(0), '0:00');
      expect(formaterDuree(75), '1:15');
      expect(formaterDuree(3725), '1:02:05');
    });

    test('date en français avec majuscule', () {
      expect(formaterDate(DateTime(2026, 7, 24, 13, 5)), contains('juillet'));
      expect(formaterDate(DateTime(2026, 7, 24)).substring(0, 1), 'V'); // Vendredi
    });

    test('titre par défaut basé sur le jour', () {
      expect(titreParDefaut(DateTime(2026, 7, 24)), 'Khoutba du vendredi 24 juillet');
    });

    test('type MIME déduit du fichier', () {
      expect(mimeSimple('/x/abc.m4a'), 'audio/mp4');
      expect(mimeSimple('/x/abc.mp3'), 'audio/mpeg');
    });

    testWidgets('le badge de statut affiche le bon libellé', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: themeClair(),
        home: const Scaffold(
          body: Column(children: [
            BadgeStatut(statut: Statut.termine),
            BadgeStatut(statut: Statut.erreur),
            BadgeStatut(statut: Statut.pret),
          ]),
        ),
      ));
      expect(find.text('Terminé'), findsOneWidget);
      expect(find.text('Erreur'), findsOneWidget);
      expect(find.text('À traiter'), findsOneWidget);
    });
  });

  group('Import audio et vidéo', () {
    test('une vidéo n’est pas annoncée comme de l’audio', () {
      // Gemini refuse une vidéo déclarée en audio/* : la distinction compte.
      expect(mimeSimple('/x/khoutba.mp4'), 'video/mp4');
      expect(mimeSimple('/x/khoutba.mov'), 'video/quicktime');
      expect(mimeSimple('/x/khoutba.3gp'), 'video/3gpp');
      expect(mimeSimple('/x/khoutba.mkv'), 'video/x-matroska');
    });

    test('les formats audio courants restent en audio/*', () {
      for (final cas in {
        'memo.m4a': 'audio/mp4',
        'memo.wav': 'audio/wav',
        'memo.ogg': 'audio/ogg',
        'memo.flac': 'audio/flac',
        'memo.amr': 'audio/amr',
        'memo.aac': 'audio/aac',
      }.entries) {
        expect(mimeSimple('/x/${cas.key}'), cas.value, reason: cas.key);
      }
    });

    test('extension inconnue : repli sans planter', () {
      expect(mimeSimple('/x/sans_extension'), 'audio/mp4');
      expect(mimeSimple('/x/truc.xyz'), 'audio/mp4');
    });

    test('les vidéos sont reconnues comme telles', () {
      expect(estVideo('/x/a.mp4'), isTrue);
      expect(estVideo('/x/a.MOV'), isTrue); // casse indifférente
      expect(estVideo('/x/a.m4a'), isFalse);
      expect(estVideo('/x/a'), isFalse);
    });

    test('découpage d’un gros fichier : couverture exacte, sans trou', () {
      // Une vidéo de prêche de 11 min pèse ~700 Mo. Un décalage d'un octet
      // enverrait un fichier corrompu sans lever la moindre erreur.
      for (final taille in [1, 100, 8 * 1024 * 1024, 8 * 1024 * 1024 + 1, 734003200]) {
        final morceaux = morceauxPour(taille);
        expect(morceaux.first.position, 0, reason: 'taille $taille');
        expect(morceaux.fold<int>(0, (t, m) => t + m.longueur), taille,
            reason: 'total envoyé ≠ taille du fichier ($taille)');
        for (var i = 1; i < morceaux.length; i++) {
          expect(morceaux[i].position, morceaux[i - 1].position + morceaux[i - 1].longueur,
              reason: 'trou ou chevauchement à $taille');
        }
        expect(morceaux.where((m) => m.dernier).length, 1,
            reason: 'un seul morceau doit clore l’envoi ($taille)');
        expect(morceaux.last.dernier, isTrue);
      }
    });

    test('découpage : cas limites', () {
      expect(morceauxPour(0), isEmpty);
      expect(morceauxPour(-5), isEmpty);
      // Un fichier plus petit qu'un morceau part en une seule fois
      final petit = morceauxPour(1024, tailleMorceau: 8192);
      expect(petit.length, 1);
      expect(petit.single.dernier, isTrue);
      // Taille exactement multiple : pas de morceau vide à la fin
      final pile = morceauxPour(16384, tailleMorceau: 8192);
      expect(pile.length, 2);
      expect(pile.every((m) => m.longueur == 8192), isTrue);
    });

    test('tous les formats proposés à l’import ont un type MIME connu', () {
      // Garde-fou : un format offert dans le sélecteur mais non reconnu
      // partirait vers l'IA avec un type erroné.
      for (final ext in [...extensionsAudio, ...extensionsVideo]) {
        final mime = mimeSimple('/x/fichier.$ext');
        expect(mime, matches(r'^(audio|video)/'), reason: '.$ext → $mime');
      }
      // Cohérence entre les deux listes et la déduction du type
      for (final ext in extensionsVideo.where((e) => e != 'webm')) {
        expect(mimeSimple('/x/f.$ext').startsWith('video/'), isTrue, reason: '.$ext');
      }
    });

  });

  group('Extraction de la piste audio', () {
    final messager = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late Directory dossier;
    late String destination;

    setUp(() {
      dossier = Directory.systemTemp.createTempSync('khoutba_extraction');
      destination = '${dossier.path}/piste.m4a';
    });

    tearDown(() {
      messager.setMockMethodCallHandler(canalExtraction, null);
      dossier.deleteSync(recursive: true);
    });

    /// Simule la partie native (Swift / Kotlin) répondant à l'app.
    void plateforme(Future<Object?>? Function(MethodCall) reponse) =>
        messager.setMockMethodCallHandler(canalExtraction, reponse);

    void ecrire(String chemin, int octets) =>
        File(chemin).writeAsBytesSync(List.filled(octets, 0));

    test('la piste extraite est celle qui sera envoyée', () async {
      plateforme((appel) async {
        expect(appel.method, 'extraire');
        expect(appel.arguments['source'], '/videos/khoutba.mp4');
        ecrire(appel.arguments['destination'], 9 * 1024 * 1024); // ~9 Mo au lieu de 700
        return appel.arguments['destination'];
      });
      final fichier = await extraireAudio('/videos/khoutba.mp4', destination);
      expect(fichier?.path, destination);
    });

    test('vidéo muette : on le dit, au lieu d’envoyer 700 Mo de silence', () async {
      plateforme((_) => throw PlatformException(code: 'sans_audio'));
      await expectLater(
        extraireAudio('/videos/muette.mp4', destination),
        throwsA(isA<ErreurExtraction>()),
      );
    });

    test('échec de l’extraction : repli sur la vidéo, sans erreur', () async {
      // Un codec inhabituel ne doit pas faire échouer l'import : l'app enverra
      // la vidéo entière, plus lourde mais exploitable.
      plateforme((_) => throw PlatformException(code: 'echec', message: 'codec inconnu'));
      expect(await extraireAudio('/videos/exotique.mkv', destination), isNull);
    });

    test('app sans partie native : repli sur la vidéo', () async {
      plateforme((_) => throw MissingPluginException());
      expect(await extraireAudio('/videos/khoutba.mp4', destination), isNull);
    });

    test('un fichier à moitié écrit n’est jamais retenu', () async {
      plateforme((appel) async {
        ecrire(appel.arguments['destination'], 300); // interrompu
        throw PlatformException(code: 'echec');
      });
      expect(await extraireAudio('/videos/khoutba.mp4', destination), isNull);
      expect(File(destination).existsSync(), isFalse, reason: 'résidu laissé sur le téléphone');
    });

    test('fichier annoncé mais absent : traité comme un échec', () async {
      plateforme((appel) async => appel.arguments['destination']);
      expect(await extraireAudio('/videos/khoutba.mp4', destination), isNull);
    });

    test('la progression remonte jusqu’à l’écran', () async {
      final vues = <double>[];
      plateforme((appel) async {
        for (final p in [0.0, 0.5, 3.0]) {
          await messager.handlePlatformMessage(
            canalExtraction.name,
            canalExtraction.codec.encodeMethodCall(MethodCall('progression', p)),
            (_) {},
          );
        }
        ecrire(appel.arguments['destination'], 2048);
        return appel.arguments['destination'];
      });
      await extraireAudio('/videos/khoutba.mp4', destination,
          onProgression: vues.add);
      expect(vues, [0.0, 0.5, 1.0]); // une valeur aberrante est ramenée à 100 %
    });

    test('un envoi lent reste visiblement vivant', () {
      // Sur 1221 Mo, chaque tranche de 8 Mo n'avance le pourcentage que de
      // 0,65 % : l'utilisateur a vu « 1 % » figé et cru l'app plantée.
      const total = 1280 * 1024 * 1024;
      String envoi(int tranches) => AvancementTraitement(
            Phase.transcription,
            progression: tranches * 8 * 1048576 / total,
            octetsEnvoyes: tranches * 8 * 1048576,
            octetsTotal: total,
          ).libelle;
      expect(envoi(1), 'Envoi du fichier… 8 / 1280 Mo');
      expect(envoi(2), 'Envoi du fichier… 16 / 1280 Mo');
      expect(envoi(1), isNot(envoi(2))); // le libellé bouge à chaque tranche
    });

    test('les étapes d’attente s’annoncent', () {
      expect(const AvancementTraitement(Phase.extraction, progression: 0.42).libelle,
          'Extraction de la piste audio… 42 %');
      expect(const AvancementTraitement(Phase.transcription).libelle, contains('Transcription'));
    });

    test('un nom de fichier technique ne devient pas un titre', () {
      // Vu sur l'iPhone : « image_picker_97CB37EA-47A1-… » en titre de khoutba.
      expect(estTitreTechnique('image_picker_97CB37EA-47A1-4F4E-B0C4-2F1A'), isTrue);
      expect(estTitreTechnique('97CB37EA-47A1-4F4E-B0C4-2F1A'), isTrue);
      expect(estTitreTechnique('IMG_4821'), isTrue);
      expect(estTitreTechnique('trim.A1B2C3'), isTrue);
      // …mais un vrai nom donné par l'utilisateur est respecté.
      expect(estTitreTechnique('Khoutba sur la patience'), isFalse);
      expect(estTitreTechnique('imam Bensalem 12-07'), isFalse);
      expect(estTitreTechnique('Enregistrement mosquée'), isFalse);
    });

    test('le format produit passe aussi chez Whisper', () {
      // L'extraction vise .m4a : si OpenAI ne l'acceptait pas, seule Gemini
      // pourrait traiter les vidéos importées.
      expect(extensionsWhisper, contains('m4a'));
      expect(mimeSimple('/x/id.m4a'), startsWith('audio/'));
    });
  });
}
