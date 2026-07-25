// Tests de la logique métier et de l'affichage, sans dépendance réseau.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:khoutba/ecrans/accueil.dart';
import 'package:khoutba/enregistreur.dart';
import 'package:khoutba/fournisseurs.dart';
import 'package:khoutba/modeles.dart';
import 'package:khoutba/theme.dart';

void main() {
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
}
