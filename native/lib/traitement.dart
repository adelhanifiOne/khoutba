// Chaîne de traitement d'une khoutba :
//   audio → 1. transcription (arabe) → 2. traduction → 3. synthèse structurée
//
// Chaque étape est sauvegardée dès qu'elle réussit : si la synthèse échoue,
// la transcription et la traduction restent acquises.

import 'dart:io';

import 'fournisseurs.dart';
import 'modeles.dart';
import 'reglages.dart';
import 'stockage.dart';

const langues = {'fr': 'français', 'en': 'anglais'};

/// Longueur max du texte envoyé à l'analyse (~1 h 30 de prêche, large).
const _maxCaracteres = 300000;

// ------------------------------------------------------------------- prompts

const promptTranscription =
    '''Transcris intégralement et fidèlement cet enregistrement audio. Il s'agit d'un prêche (khoutba) prononcé dans une mosquée, principalement en arabe littéraire, parfois mêlé de dialecte algérien.

Consignes :
- Écris la transcription en arabe, avec la ponctuation, découpée en paragraphes.
- Ne traduis pas, ne résume pas, n'ajoute aucun commentaire.
- Ignore l'adhan, les bruits de fond et les répétitions techniques (micro).
- Si un passage est incompréhensible, écris [غير مسموع].
- Commence directement par le texte, sans introduction.''';

String promptSystemTraduction(String langue) =>
    '''Tu es un traducteur professionnel arabe → $langue, spécialisé dans le discours religieux musulman (khoutbas du vendredi).

Règles :
- Traduis fidèlement et intégralement, sans résumer ni omettre de passages.
- Conserve le découpage en paragraphes du texte d'origine.
- Pour les versets du Coran : donne une traduction soignée entre guillemets « … », suivie de la référence (sourate, numéro:verset) si tu l'identifies avec certitude.
- Pour les hadiths : traduis, et indique la source entre parenthèses si elle est citée ou connue.
- Rends les formules pieuses de façon naturelle (ex. : ﷺ → « que la paix et le salut soient sur lui »).
- Si le texte contient [غير مسموع], écris [inaudible].
- Réponds uniquement avec la traduction, sans préambule ni commentaire.''';

String promptSystemSynthese(String langue) =>
    '''Tu es un assistant qui aide un fidèle francophone à comprendre la khoutba du vendredi qu'il a enregistrée à la mosquée. À partir de la transcription arabe fournie, produis une synthèse claire et fidèle en $langue, au format JSON demandé.

Consignes :
- "titre" : un titre court et parlant pour cette khoutba.
- "theme" : le sujet principal en une ou deux phrases.
- "resume" : un résumé fidèle en deux à quatre paragraphes (séparés par des sauts de ligne), qui suit le fil du prêche.
- "points_cles" : 4 à 8 idées essentielles, formulées simplement.
- "citations" : les versets du Coran et hadiths cités : texte arabe exact tel qu'entendu, traduction, et référence ("type" vaut "coran", "hadith" ou "autre" ; si la référence est incertaine, écris "référence à vérifier").
- "conseils" : les recommandations pratiques données par l'imam, applicables au quotidien.
- "douas" : les invocations notables de la fin du prêche, traduites (liste vide si aucune).
- N'invente rien : tout doit venir de la transcription. En cas de doute, signale-le.''';

const schemaSynthese = <String, dynamic>{
  'type': 'object',
  'properties': {
    'titre': {'type': 'string'},
    'theme': {'type': 'string'},
    'resume': {'type': 'string'},
    'points_cles': {
      'type': 'array',
      'items': {'type': 'string'}
    },
    'citations': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'type': {
            'type': 'string',
            'enum': ['coran', 'hadith', 'autre']
          },
          'texte_arabe': {'type': 'string'},
          'traduction': {'type': 'string'},
          'reference': {'type': 'string'},
        },
        'required': ['type', 'texte_arabe', 'traduction', 'reference'],
        'additionalProperties': false,
      },
    },
    'conseils': {
      'type': 'array',
      'items': {'type': 'string'}
    },
    'douas': {
      'type': 'array',
      'items': {'type': 'string'}
    },
  },
  'required': ['titre', 'theme', 'resume', 'points_cles', 'citations', 'conseils', 'douas'],
  'additionalProperties': false,
};

// -------------------------------------------------------------- orchestration

enum Phase { transcription, traduction, synthese, termine }

class AvancementTraitement {
  final Phase phase;
  final String? partiel;
  const AvancementTraitement(this.phase, {this.partiel});

  String get libelle {
    switch (phase) {
      case Phase.transcription:
        return 'Transcription de l’arabe en cours… (quelques minutes)';
      case Phase.traduction:
        final n = partiel == null ? '' : ' — ${partiel!.length} caractères';
        return 'Traduction en cours…$n';
      case Phase.synthese:
        return 'Rédaction du résumé et des points clés…';
      case Phase.termine:
        return 'Terminé';
    }
  }
}

class Traitement {
  static bool _enCours = false;
  static bool get enCours => _enCours;

  static String _cle(Reglages r, String fournisseur) {
    final cle = r.cles[fournisseur] ?? '';
    if (cle.isEmpty) {
      const noms = {'gemini': 'Gemini', 'openai': 'OpenAI', 'anthropic': 'Claude (Anthropic)'};
      throw ErreurIA('Clé API ${noms[fournisseur]} manquante — ajoute-la dans les réglages.');
    }
    return cle;
  }

  static Future<String> _transcrire(Enregistrement rec, Reglages r) async {
    final stt = r.demo ? 'demo' : r.stt;
    final fichier = File(rec.cheminAudio);
    if (!await fichier.exists() && stt != 'demo') {
      throw ErreurIA('Fichier audio introuvable — il a peut-être été supprimé.');
    }
    switch (stt) {
      case 'demo':
        return ClientDemo().transcrire();
      case 'gemini':
        return ClientGemini(_cle(r, 'gemini'))
            .transcrire(fichier, promptTranscription, modele: r.modeleGemini);
      case 'openai':
        return ClientOpenAI(_cle(r, 'openai')).transcrire(fichier);
      default:
        throw ErreurIA('Choisis un service de transcription dans les réglages (Gemini ou OpenAI).');
    }
  }

  static Future<String> _generer(
    Reglages r, {
    required String system,
    required String user,
    Map<String, dynamic>? schema,
    void Function(String)? onDelta,
  }) async {
    final llm = r.demo ? 'demo' : r.llm;
    switch (llm) {
      case 'demo':
        return ClientDemo().generer(schema: schema, onDelta: onDelta);
      case 'gemini':
        final texte = await ClientGemini(_cle(r, 'gemini')).generer(
          system: system,
          user: user,
          json: schema != null,
          modele: r.modeleGemini,
        );
        onDelta?.call(texte);
        return texte;
      case 'openai':
        return ClientOpenAI(_cle(r, 'openai'))
            .generer(system: system, user: user, schema: schema, onDelta: onDelta);
      case 'anthropic':
        return ClientClaude(_cle(r, 'anthropic'), modele: r.modeleClaude).generer(
          system: system,
          user: user,
          schema: schema,
          onDelta: onDelta,
          reflexion: schema != null,
        );
      default:
        throw ErreurIA('Choisis un service de traduction/synthèse dans les réglages.');
    }
  }

  /// Traite un enregistrement de bout en bout. `forcer` relance tout,
  /// y compris les étapes déjà faites.
  static Future<void> lancer(
    Enregistrement rec,
    Reglages r, {
    void Function(AvancementTraitement)? onAvancement,
    bool forcer = false,
  }) async {
    if (_enCours) {
      throw ErreurIA('Un traitement est déjà en cours — attends qu’il se termine.');
    }
    _enCours = true;
    final langue = langues[r.langue] ?? langues['fr']!;

    try {
      // 1. Transcription
      if (rec.transcription == null || forcer) {
        rec.statut = Statut.transcription;
        rec.erreur = null;
        await Stockage.sauver(rec);
        onAvancement?.call(const AvancementTraitement(Phase.transcription));
        rec.transcription = (await _transcrire(rec, r)).trim();
        rec.statut = Statut.transcrit;
        await Stockage.sauver(rec);
      }

      final source = rec.transcription!.length > _maxCaracteres
          ? rec.transcription!.substring(0, _maxCaracteres)
          : rec.transcription!;

      // 2. Traduction
      if (rec.traduction == null || forcer) {
        rec.statut = Statut.traduction;
        await Stockage.sauver(rec);
        onAvancement?.call(const AvancementTraitement(Phase.traduction));
        rec.traduction = (await _generer(
          r,
          system: promptSystemTraduction(langue),
          user: 'Voici la transcription de la khoutba à traduire :\n\n$source',
          onDelta: (t) => onAvancement?.call(AvancementTraitement(Phase.traduction, partiel: t)),
        )).trim();
        rec.statut = Statut.traduit;
        await Stockage.sauver(rec);
      }

      // 3. Synthèse structurée
      rec.statut = Statut.synthese;
      await Stockage.sauver(rec);
      onAvancement?.call(const AvancementTraitement(Phase.synthese));
      final brut = await _generer(
        r,
        system: promptSystemSynthese(langue),
        user: 'Voici la transcription arabe de la khoutba :\n\n$source\n\n'
            'Réponds uniquement avec le JSON demandé.',
        schema: schemaSynthese,
      );
      final synthese = Synthese.depuisJson(parseJsonSouple(brut));
      if (synthese.titre.isEmpty || synthese.resume.isEmpty) {
        throw ErreurIA('Synthèse incomplète renvoyée par le modèle — réessaie.');
      }
      rec.synthese = synthese;
      rec.statut = Statut.termine;
      rec.erreur = null;
      if (!rec.titrePerso && synthese.titre.isNotEmpty) rec.titre = synthese.titre;
      await Stockage.sauver(rec);
      onAvancement?.call(const AvancementTraitement(Phase.termine));
    } catch (e) {
      rec.statut = Statut.erreur;
      rec.erreur = e is ErreurIA ? e.message : e.toString();
      await Stockage.sauver(rec);
      rethrow;
    } finally {
      _enCours = false;
    }
  }
}
