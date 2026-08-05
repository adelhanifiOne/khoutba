// Connecteurs vers les API d'IA. Les appels partent directement du téléphone :
// les clés restent sur l'appareil, l'audio n'est envoyé qu'au service choisi.
//
// - Gemini : transcription (audio natif) + traduction/synthèse
// - OpenAI : transcription Whisper + traduction/synthèse (GPT)
// - Claude  : traduction/synthèse
// - démo    : contenu fictif, pour essayer sans clé

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

class ErreurIA implements Exception {
  final String message;
  final bool modeleIndisponible;
  ErreurIA(this.message, {this.modeleIndisponible = false});
  @override
  String toString() => message;
}

class ModelesParDefaut {
  // Le modèle Gemini n'est pas figé : Google en retire régulièrement
  // (« no longer available to new users »). Ces noms ne servent que si la
  // liste des modèles disponibles est inaccessible.
  static const geminiSecours = ['gemini-flash-latest', 'gemini-2.5-flash', 'gemini-2.0-flash'];
  static const openaiTranscription = 'whisper-1';
  static const openaiTexte = 'gpt-4o-mini';
  static const claude = 'claude-opus-4-8';
}

const choixModelesClaude = <String, String>{
  'claude-opus-4-8': 'Claude Opus 4.8 — meilleure qualité',
  'claude-sonnet-5': 'Claude Sonnet 5 — rapide et équilibré',
  'claude-haiku-4-5': 'Claude Haiku 4.5 — le plus économique',
};

// --------------------------------------------------------------- utilitaires

const _delaiCourt = Duration(seconds: 60);
const _delaiLong = Duration(minutes: 15); // transcription d'une khoutba entière

ErreurIA _erreurHttp(String nom, int statut, String corps) {
  var detail = corps;
  try {
    final j = jsonDecode(corps);
    if (j is Map && j['error'] is Map) {
      detail = (j['error']['message'] ?? j['error']['type'] ?? corps).toString();
    }
  } catch (_) {}
  if (detail.length > 300) detail = '${detail.substring(0, 300)}…';
  final indispo = statut == 404 ||
      (statut == 400 &&
          RegExp('not supported|unsupported|no longer available', caseSensitive: false)
              .hasMatch(detail));
  return ErreurIA('$nom : erreur $statut — $detail', modeleIndisponible: indispo);
}

/// Erreur de transport. La cause réelle est conservée : sans elle, un délai
/// dépassé, un manque de mémoire ou un refus TLS se ressemblent tous, et on
/// accuse à tort la connexion de l'utilisateur.
Never _erreurReseau(String nom, Object cause) {
  if (cause is TimeoutException) {
    throw ErreurIA(
      '$nom : délai dépassé. Le fichier est peut-être trop lourd pour ta connexion — '
      'réessaie en Wi-Fi, ou avec un extrait plus court.',
    );
  }
  var detail = cause.toString();
  if (cause is http.ClientException) detail = cause.message;
  if (cause is SocketException) {
    throw ErreurIA('$nom : pas de connexion au service (${cause.osError?.message ?? 'réseau injoignable'}).');
  }
  if (detail.length > 200) detail = '${detail.substring(0, 200)}…';
  throw ErreurIA('$nom : échec de l’envoi — $detail');
}

/// Type MIME du fichier, déduit de son extension.
///
/// La distinction audio / vidéo compte : Gemini accepte les deux, mais refuse
/// une vidéo annoncée comme de l'audio.
String mimeSimple(String chemin) {
  final ext = chemin.toLowerCase().split('.').last;
  switch (ext) {
    // Audio
    case 'm4a':
    case 'caf':
      return 'audio/mp4';
    case 'aac':
      return 'audio/aac';
    case 'mp3':
    case 'mpga':
      return 'audio/mpeg';
    case 'wav':
      return 'audio/wav';
    case 'ogg':
    case 'oga':
    case 'opus':
      return 'audio/ogg';
    case 'flac':
      return 'audio/flac';
    case 'amr':
      return 'audio/amr';
    case 'webm':
      return 'audio/webm';
    // Vidéo — la piste sonore est extraite par le service
    case 'mp4':
    case 'm4v':
      return 'video/mp4';
    case 'mov':
      return 'video/quicktime';
    case '3gp':
      return 'video/3gpp';
    case 'avi':
      return 'video/x-msvideo';
    case 'mkv':
      return 'video/x-matroska';
    case 'mpeg':
    case 'mpg':
      return 'video/mpeg';
    default:
      return 'audio/mp4';
  }
}

/// Extensions acceptées par Whisper (OpenAI). Les autres doivent passer par
/// Gemini, qui prend la vidéo nativement.
const _extensionsWhisper = {
  'flac', 'm4a', 'mp3', 'mp4', 'mpeg', 'mpga', 'oga', 'ogg', 'wav', 'webm'
};

/// Le modèle renvoie parfois le JSON entouré de ```json … ``` : on nettoie.
Map<String, dynamic> parseJsonSouple(String texte) {
  var t = texte.trim();
  if (t.isEmpty) throw ErreurIA('Réponse vide du modèle.');
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(t);
  if (fence != null) t = fence.group(1)!.trim();
  try {
    final v = jsonDecode(t);
    if (v is Map<String, dynamic>) return v;
  } catch (_) {}
  final debut = t.indexOf('{');
  final fin = t.lastIndexOf('}');
  if (debut >= 0 && fin > debut) {
    final v = jsonDecode(t.substring(debut, fin + 1));
    if (v is Map<String, dynamic>) return v;
  }
  throw ErreurIA('Le modèle n’a pas renvoyé un JSON valide.');
}

// -------------------------------------------------------------------- Gemini

const _geminiBase = 'https://generativelanguage.googleapis.com';
const _limiteInline = 15 * 1024 * 1024; // au-delà : upload via l'API Files
const tailleMorceauEnvoi = 8 * 1024 * 1024; // envoi tranche par tranche

/// Un morceau de fichier à envoyer.
class MorceauEnvoi {
  final int position;
  final int longueur;
  final bool dernier;
  const MorceauEnvoi(this.position, this.longueur, this.dernier);
}

/// Découpe un fichier de [taille] octets en morceaux consécutifs.
/// Fonction pure : un décalage d'un octet corromprait le fichier envoyé
/// sans qu'aucune erreur ne le signale, d'où les tests dédiés.
List<MorceauEnvoi> morceauxPour(int taille, {int tailleMorceau = tailleMorceauEnvoi}) {
  if (taille <= 0) return const [];
  final morceaux = <MorceauEnvoi>[];
  var position = 0;
  while (position < taille) {
    final longueur = math.min(tailleMorceau, taille - position);
    morceaux.add(MorceauEnvoi(position, longueur, position + longueur >= taille));
    position += longueur;
  }
  return morceaux;
}

class ModeleGemini {
  final String id;
  final String nom;
  const ModeleGemini(this.id, this.nom);
}

/// Modèles à écarter : ni génératifs de texte, ni compatibles audio.
final _geminiExclus = RegExp(
  r'(embedding|aqa|imagen|veo|gemma|tts|image-generation|native-audio|-live-|learnlm|vision)',
  caseSensitive: false,
);

/// Écarte les modèles inadaptés et classe les autres, du plus au moins adapté.
/// Fonction pure : testable sans réseau.
List<ModeleGemini> classerModelesGemini(List<ModeleGemini> modeles) {
  final retenus = modeles
      .where((m) =>
          m.id.isNotEmpty && !_geminiExclus.hasMatch(m.id) && !_geminiExclus.hasMatch(m.nom))
      .toList();
  retenus.sort((a, b) => _scoreModeleGemini(b.id).compareTo(_scoreModeleGemini(a.id)));
  return retenus;
}

int _scoreModeleGemini(String id) {
  int score;
  if (id.contains('flash') && !id.contains('lite')) {
    score = 1000; // le bon compromis qualité / prix / vitesse
  } else if (RegExp(r'(^|-)pro(-|$)').hasMatch(id)) {
    score = 700;
  } else if (id.contains('lite')) {
    score = 500;
  } else {
    score = 300;
  }
  final v = RegExp(r'gemini-(\d+(?:\.\d+)?)').firstMatch(id)?.group(1);
  score += ((double.tryParse(v ?? '0') ?? 0) * 10).round();
  if (RegExp(r'(preview|exp|beta|\d{4}-\d{2}|-\d{3,})').hasMatch(id)) score -= 50;
  if (id.endsWith('-latest')) score += 5;
  return score;
}

class ClientGemini {
  final String cle;
  ClientGemini(this.cle);

  static List<String>? _candidats;
  static String _cleCache = '';
  static String modeleRetenu = '';

  static void reinitialiser() {
    _candidats = null;
    _cleCache = '';
    modeleRetenu = '';
  }

  /// Modèles utilisables avec cette clé, du plus adapté au moins adapté.
  Future<List<ModeleGemini>> listerModeles() async {
    final url = Uri.parse('$_geminiBase/v1beta/models?pageSize=200&key=$cle');
    http.Response rep;
    try {
      rep = await http.get(url).timeout(_delaiCourt);
    } catch (e) {
      _erreurReseau('Gemini', e);
    }
    if (rep.statusCode != 200) throw _erreurHttp('Gemini', rep.statusCode, rep.body);
    final data = jsonDecode(utf8.decode(rep.bodyBytes));
    final liste = <ModeleGemini>[];
    for (final m in (data['models'] as List? ?? const [])) {
      if (m is! Map) continue;
      final methodes = (m['supportedGenerationMethods'] as List? ?? const []);
      if (!methodes.contains('generateContent')) continue;
      liste.add(ModeleGemini(
        (m['name'] ?? '').toString().replaceFirst('models/', ''),
        (m['displayName'] ?? '').toString(),
      ));
    }
    return classerModelesGemini(liste);
  }

  Future<List<String>> _listeCandidats(String? modeleForce) async {
    if (modeleForce != null && modeleForce.isNotEmpty) return [modeleForce];
    if (_candidats != null && _cleCache == cle) return _candidats!;
    try {
      final liste = await listerModeles();
      _candidats = liste.isNotEmpty
          ? liste.map((m) => m.id).toList()
          : List<String>.from(ModelesParDefaut.geminiSecours);
    } catch (_) {
      // Liste inaccessible (réseau, quota…) : on tente les noms connus.
      _candidats = List<String>.from(ModelesParDefaut.geminiSecours);
    }
    _cleCache = cle;
    return _candidats!;
  }

  Future<String> _appel(
    String modele,
    List<Map<String, dynamic>> contents,
    Map<String, dynamic> generationConfig,
    String? systemInstruction,
    Duration delai,
  ) async {
    final corps = <String, dynamic>{'contents': contents, 'generationConfig': generationConfig};
    if (systemInstruction != null) {
      corps['systemInstruction'] = {
        'parts': [
          {'text': systemInstruction}
        ]
      };
    }
    final url = Uri.parse('$_geminiBase/v1beta/models/$modele:generateContent?key=$cle');
    http.Response rep;
    try {
      rep = await http
          .post(url, headers: {'content-type': 'application/json'}, body: jsonEncode(corps))
          .timeout(delai);
    } catch (e) {
      _erreurReseau('Gemini', e);
    }

    if (rep.statusCode != 200) {
      // Certains réglages (thinkingConfig…) ne sont pas acceptés partout :
      // on retente une fois sans, plutôt que d'échouer.
      if (rep.statusCode == 400 && generationConfig.containsKey('thinkingConfig')) {
        final reste = Map<String, dynamic>.from(generationConfig)..remove('thinkingConfig');
        return _appel(modele, contents, reste, systemInstruction, delai);
      }
      throw _erreurHttp('Gemini', rep.statusCode, utf8.decode(rep.bodyBytes));
    }

    final data = jsonDecode(utf8.decode(rep.bodyBytes));
    final cand = (data['candidates'] as List?)?.firstOrNull;
    final parts = (cand?['content']?['parts'] as List? ?? const []);
    final texte = parts.map((p) => (p['text'] ?? '').toString()).join();
    if (texte.trim().isEmpty) {
      final raison = data['promptFeedback']?['blockReason'] ?? cand?['finishReason'] ?? 'réponse vide';
      throw ErreurIA('Gemini n’a pas renvoyé de texte ($raison).');
    }
    return texte;
  }

  /// Essaie les modèles disponibles dans l'ordre, jusqu'à en trouver un qui répond.
  Future<String> _genererAvecRepli(
    List<Map<String, dynamic>> contents,
    Map<String, dynamic> generationConfig,
    String? systemInstruction,
    String? modeleForce,
    Duration delai,
  ) async {
    final candidats = await _listeCandidats(modeleForce);
    Object? derniere;
    for (final modele in candidats.take(4)) {
      try {
        final texte = await _appel(modele, contents, generationConfig, systemInstruction, delai);
        modeleRetenu = modele;
        return texte;
      } on ErreurIA catch (e) {
        derniere = e;
        if (!e.modeleIndisponible) rethrow; // vraie erreur (clé, quota, contenu)
        _candidats = null; // ce modèle a disparu : on re-listera
      }
    }
    throw derniere ?? ErreurIA('Gemini : aucun modèle disponible avec cette clé.');
  }

  /// Envoie un morceau, avec quelques tentatives : sur un réseau mobile, une
  /// coupure passagère ne doit pas condamner un envoi de plusieurs minutes.
  Future<http.Response> _envoyerMorceau(
      String url, List<int> morceau, int position, bool dernier) async {
    Object? derniereErreur;
    for (var tentative = 1; tentative <= 3; tentative++) {
      try {
        final rep = await http.post(
          Uri.parse(url),
          headers: {
            'x-goog-upload-offset': '$position',
            'x-goog-upload-command': dernier ? 'upload, finalize' : 'upload',
            'content-type': 'application/octet-stream',
          },
          body: morceau,
        ).timeout(_delaiLong);
        if (rep.statusCode == 200) return rep;
        // Une erreur 4xx ne s'arrangera pas en insistant.
        if (rep.statusCode < 500) {
          throw _erreurHttp('Gemini (envoi du fichier)', rep.statusCode, rep.body);
        }
        derniereErreur = ErreurIA('erreur ${rep.statusCode}');
      } on ErreurIA {
        rethrow;
      } catch (e) {
        derniereErreur = e;
      }
      await Future.delayed(Duration(seconds: 2 * tentative));
    }
    _erreurReseau('Gemini (envoi du fichier)', derniereErreur!);
  }

  Future<Map<String, dynamic>> _televerserFichier(
    File fichier,
    String mime, {
    void Function(int envoye, int total)? onProgression,
  }) async {
    final taille = await fichier.length();
    http.Response rep;
    try {
      rep = await http.post(
        Uri.parse('$_geminiBase/upload/v1beta/files?key=$cle'),
        headers: {
          'x-goog-upload-protocol': 'resumable',
          'x-goog-upload-command': 'start',
          'x-goog-upload-header-content-length': '$taille',
          'x-goog-upload-header-content-type': mime,
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'file': {'display_name': 'khoutba-audio'}
        }),
      ).timeout(_delaiCourt);
    } catch (e) {
      _erreurReseau('Gemini (ouverture de l’envoi)', e);
    }
    if (rep.statusCode != 200) {
      throw _erreurHttp('Gemini (ouverture de l’envoi)', rep.statusCode, rep.body);
    }
    final urlUpload = rep.headers['x-goog-upload-url'];
    if (urlUpload == null) throw ErreurIA('Gemini : URL de téléversement absente.');

    // Envoi par morceaux. Une vidéo de prêche pèse facilement plusieurs
    // centaines de mégaoctets : la charger entièrement en mémoire fait tuer
    // l'app par le système. On lit le fichier tranche par tranche.
    final acces = await fichier.open();
    http.Response? rep2;
    try {
      for (final m in morceauxPour(taille)) {
        await acces.setPosition(m.position);
        final donnees = await acces.read(m.longueur);
        rep2 = await _envoyerMorceau(urlUpload, donnees, m.position, m.dernier);
        onProgression?.call(m.position + m.longueur, taille);
      }
    } finally {
      await acces.close();
    }
    if (rep2 == null) throw ErreurIA('Gemini : fichier vide, rien à envoyer.');

    var info = Map<String, dynamic>.from(jsonDecode(utf8.decode(rep2.bodyBytes))['file']);
    // Attendre la fin du traitement côté Google (≈ quelques secondes).
    final debut = DateTime.now();
    while (info['state'] == 'PROCESSING') {
      if (DateTime.now().difference(debut) > const Duration(minutes: 5)) {
        throw ErreurIA('Gemini : le traitement du fichier audio prend trop de temps.');
      }
      await Future.delayed(const Duration(seconds: 3));
      final r = await http
          .get(Uri.parse('$_geminiBase/v1beta/${info['name']}?key=$cle'))
          .timeout(_delaiCourt);
      if (r.statusCode != 200) throw _erreurHttp('Gemini', r.statusCode, r.body);
      info = Map<String, dynamic>.from(jsonDecode(utf8.decode(r.bodyBytes)));
    }
    if (info['state'] != 'ACTIVE') {
      throw ErreurIA('Gemini : fichier audio refusé (état ${info['state']}).');
    }
    return info;
  }

  Future<String> transcrire(
    File audio,
    String prompt, {
    String? modele,
    void Function(int envoye, int total)? onProgression,
  }) async {
    final mime = mimeSimple(audio.path);
    final Map<String, dynamic> partAudio;
    if (await audio.length() <= _limiteInline) {
      partAudio = {
        'inlineData': {'mimeType': mime, 'data': base64Encode(await audio.readAsBytes())}
      };
    } else {
      final fichier = await _televerserFichier(audio, mime, onProgression: onProgression);
      partAudio = {
        'fileData': {'mimeType': mime, 'fileUri': fichier['uri']}
      };
    }
    return _genererAvecRepli(
      [
        {
          'role': 'user',
          'parts': [
            partAudio,
            {'text': prompt}
          ]
        }
      ],
      {
        'temperature': 0.2,
        'maxOutputTokens': 65536,
        // La transcription n'a pas besoin de « réflexion » : plus rapide, moins cher.
        'thinkingConfig': {'thinkingBudget': 0},
      },
      null,
      modele,
      _delaiLong,
    );
  }

  Future<String> generer({
    required String system,
    required String user,
    bool json = false,
    String? modele,
  }) {
    final config = <String, dynamic>{'temperature': 0.3, 'maxOutputTokens': 65536};
    if (json) config['responseMimeType'] = 'application/json';
    return _genererAvecRepli(
      [
        {
          'role': 'user',
          'parts': [
            {'text': user}
          ]
        }
      ],
      config,
      system,
      modele,
      _delaiLong,
    );
  }
}

// -------------------------------------------------------------------- OpenAI

const _openaiBase = 'https://api.openai.com';
const _limiteWhisper = 25 * 1024 * 1024;

class ClientOpenAI {
  final String cle;
  ClientOpenAI(this.cle);

  Future<String> transcrire(File audio) async {
    final ext = audio.path.toLowerCase().split('.').last;
    if (!_extensionsWhisper.contains(ext)) {
      throw ErreurIA(
        'Whisper (OpenAI) n’accepte pas les fichiers « .$ext ». '
        'Choisis Gemini pour la transcription dans les réglages : il prend ce format.',
      );
    }
    final taille = await audio.length();
    if (taille > _limiteWhisper) {
      throw ErreurIA(
        'Fichier trop gros pour Whisper (${(taille / 1048576).toStringAsFixed(1)} Mo, limite 25 Mo). '
        'Les vidéos dépassent vite cette limite : choisis Gemini dans les réglages, '
        'il accepte des fichiers bien plus longs.',
      );
    }
    final requete = http.MultipartRequest('POST', Uri.parse('$_openaiBase/v1/audio/transcriptions'))
      ..headers['authorization'] = 'Bearer $cle'
      ..fields['model'] = ModelesParDefaut.openaiTranscription
      ..fields['language'] = 'ar'
      ..fields['response_format'] = 'text'
      ..fields['temperature'] = '0'
      ..files.add(await http.MultipartFile.fromPath('file', audio.path));

    http.Response rep;
    try {
      rep = await http.Response.fromStream(await requete.send().timeout(_delaiLong));
    } catch (e) {
      _erreurReseau('OpenAI (Whisper)', e);
    }
    if (rep.statusCode != 200) {
      throw _erreurHttp('OpenAI (Whisper)', rep.statusCode, utf8.decode(rep.bodyBytes));
    }
    return utf8.decode(rep.bodyBytes).trim();
  }

  Future<String> generer({
    required String system,
    required String user,
    Map<String, dynamic>? schema,
    void Function(String)? onDelta,
  }) async {
    final corps = <String, dynamic>{
      'model': ModelesParDefaut.openaiTexte,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
      'stream': true,
      'max_completion_tokens': 16000,
    };
    if (schema != null) {
      corps['response_format'] = {
        'type': 'json_schema',
        'json_schema': {'name': 'synthese_khoutba', 'strict': true, 'schema': schema},
      };
    }

    final requete = http.Request('POST', Uri.parse('$_openaiBase/v1/chat/completions'))
      ..headers['authorization'] = 'Bearer $cle'
      ..headers['content-type'] = 'application/json'
      ..body = jsonEncode(corps);

    return _lireFluxSSE(
      nom: 'OpenAI',
      requete: requete,
      extraire: (obj) => obj['choices']?[0]?['delta']?['content']?.toString(),
      onDelta: onDelta,
    );
  }
}

// ----------------------------------------------------------------- Anthropic

const _anthropicBase = 'https://api.anthropic.com';

class ClientClaude {
  final String cle;
  final String modele;
  ClientClaude(this.cle, {String? modele}) : modele = modele ?? ModelesParDefaut.claude;

  Future<String> generer({
    required String system,
    required String user,
    Map<String, dynamic>? schema,
    void Function(String)? onDelta,
    bool reflexion = false,
  }) async {
    final corps = <String, dynamic>{
      'model': modele,
      'max_tokens': schema != null ? 16000 : 32000,
      'system': system,
      'messages': [
        {'role': 'user', 'content': user}
      ],
      'stream': true,
    };
    // Réflexion adaptative pour l'analyse (repérer versets et hadiths demande
    // un peu de raisonnement) ; inutile pour la traduction pure.
    if (reflexion) corps['thinking'] = {'type': 'adaptive'};
    if (schema != null) {
      corps['output_config'] = {
        'format': {'type': 'json_schema', 'schema': schema}
      };
    }

    final requete = http.Request('POST', Uri.parse('$_anthropicBase/v1/messages'))
      ..headers['x-api-key'] = cle
      ..headers['anthropic-version'] = '2023-06-01'
      ..headers['content-type'] = 'application/json'
      ..body = jsonEncode(corps);

    var stopReason = '';
    final texte = await _lireFluxSSE(
      nom: 'Claude',
      requete: requete,
      extraire: (obj) {
        if (obj['type'] == 'content_block_delta' && obj['delta']?['type'] == 'text_delta') {
          return obj['delta']['text']?.toString();
        }
        if (obj['type'] == 'message_delta' && obj['delta']?['stop_reason'] != null) {
          stopReason = obj['delta']['stop_reason'].toString();
        }
        if (obj['type'] == 'error') {
          throw ErreurIA('Claude : ${obj['error']?['message'] ?? 'erreur de flux'}');
        }
        return null;
      },
      onDelta: onDelta,
    );
    if (stopReason == 'refusal') throw ErreurIA('Claude a refusé de traiter ce contenu.');
    if (stopReason == 'max_tokens') {
      return '$texte\n\n[… réponse tronquée : texte trop long]';
    }
    return texte;
  }
}

/// Lit un flux SSE (`data: {...}`) et assemble le texte au fil de l'eau.
Future<String> _lireFluxSSE({
  required String nom,
  required http.Request requete,
  required String? Function(Map<String, dynamic>) extraire,
  void Function(String)? onDelta,
}) async {
  http.StreamedResponse rep;
  final client = http.Client();
  try {
    try {
      rep = await client.send(requete).timeout(_delaiLong);
    } catch (e) {
      _erreurReseau(nom, e);
    }
    if (rep.statusCode != 200) {
      final corps = await rep.stream.bytesToString();
      throw _erreurHttp(nom, rep.statusCode, corps);
    }

    final tampon = StringBuffer();
    await for (final ligne in rep.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      final l = ligne.trim();
      if (!l.startsWith('data:')) continue;
      final charge = l.substring(5).trim();
      if (charge.isEmpty || charge == '[DONE]') continue;
      Map<String, dynamic> obj;
      try {
        final v = jsonDecode(charge);
        if (v is! Map<String, dynamic>) continue;
        obj = v;
      } catch (_) {
        continue;
      }
      final morceau = extraire(obj);
      if (morceau != null && morceau.isNotEmpty) {
        tampon.write(morceau);
        onDelta?.call(tampon.toString());
      }
    }
    return tampon.toString();
  } finally {
    client.close();
  }
}

// ---------------------------------------------------------------------- Démo

const _demoTranscription = '''الحمد لله ربّ العالمين، والصلاة والسلام على أشرف المرسلين، سيدنا محمد وعلى آله وصحبه أجمعين. أما بعد، فيا عباد الله، أوصيكم ونفسي بتقوى الله عز وجل.

عباد الله، إنّ نعم الله علينا لا تُعدّ ولا تُحصى: نعمة الإيمان، ونعمة الصحة، ونعمة الأمن، ونعمة الأهل والولد. قال الله تعالى: «وَإِذْ تَأَذَّنَ رَبُّكُمْ لَئِن شَكَرْتُمْ لَأَزِيدَنَّكُمْ وَلَئِن كَفَرْتُمْ إِنَّ عَذَابِي لَشَدِيدٌ».

فالشكر يكون بالقلب واللسان والجوارح. وقال رسول الله صلى الله عليه وسلم: «لا يشكر اللهَ من لا يشكر الناس».

فاتقوا الله عباد الله، واشكروه على نعمه يزدكم من فضله، وحافظوا على الصلاة في وقتها. أقول قولي هذا وأستغفر الله لي ولكم.''';

const _demoTraduction =
    '''Louange à Allah, Seigneur des mondes. Que la paix et le salut soient sur le plus noble des messagers, notre maître Mohammed ﷺ, ainsi que sur sa famille et l'ensemble de ses compagnons. Ceci étant dit : ô serviteurs d'Allah, je vous recommande, à vous comme à moi-même, la crainte d'Allah.

Serviteurs d'Allah, les bienfaits d'Allah sur nous ne se comptent pas : le bienfait de la foi, celui de la santé, celui de la sécurité, celui de la famille et des enfants. Allah le Très-Haut a dit : « Et lorsque votre Seigneur proclama : si vous êtes reconnaissants, très certainement J'augmenterai [Mes bienfaits] pour vous ; mais si vous êtes ingrats, Mon châtiment sera terrible » (Ibrahim, 14:7).

La gratitude s'exprime par le cœur, par la langue et par les membres. Le Messager d'Allah ﷺ a dit : « Ne remercie pas Allah celui qui ne remercie pas les gens ».

Craignez donc Allah, remerciez-Le pour Ses bienfaits, Il vous en accordera davantage par Sa grâce, et préservez la prière à son heure. Je dis ces paroles et je demande pardon à Allah pour moi et pour vous.''';

const _demoSynthese = {
  'titre': 'La gratitude envers Allah (ach-choukr)',
  'theme':
      "Reconnaître les bienfaits d'Allah et les faire fructifier par la reconnaissance du cœur, de la langue et des actes.",
  'resume':
      "L'imam rappelle que les bienfaits d'Allah — la foi, la santé, la sécurité, la famille — sont innombrables, et que la gratitude est la clé de leur préservation et de leur augmentation, comme le promet le verset de la sourate Ibrahim.\n\nIl détaille ensuite les trois niveaux de la gratitude : celle du cœur, celle de la langue et celle des membres. Il conclut en liant la gratitude envers Allah à la gratitude envers les gens, et exhorte à préserver la prière à son heure.",
  'points_cles': [
    "Les bienfaits d'Allah sont innombrables : foi, santé, sécurité, famille.",
    'La gratitude fait augmenter les bienfaits ; l’ingratitude expose au châtiment.',
    'Trois niveaux de gratitude : le cœur, la langue, les membres.',
    'Remercier les gens fait partie de la gratitude envers Allah.',
    'Préserver la prière à son heure.',
  ],
  'citations': [
    {
      'type': 'coran',
      'texte_arabe':
          'وَإِذْ تَأَذَّنَ رَبُّكُمْ لَئِن شَكَرْتُمْ لَأَزِيدَنَّكُمْ وَلَئِن كَفَرْتُمْ إِنَّ عَذَابِي لَشَدِيدٌ',
      'traduction':
          "Et lorsque votre Seigneur proclama : si vous êtes reconnaissants, très certainement J'augmenterai [Mes bienfaits] pour vous ; mais si vous êtes ingrats, Mon châtiment sera terrible.",
      'reference': 'Sourate Ibrahim, 14:7',
    },
    {
      'type': 'hadith',
      'texte_arabe': 'لا يشكر اللهَ من لا يشكر الناس',
      'traduction': 'Ne remercie pas Allah celui qui ne remercie pas les gens.',
      'reference': 'Abou Dawoud et at-Tirmidhi',
    },
  ],
  'conseils': [
    'Prendre un moment chaque jour pour énumérer les bienfaits reçus et dire al-hamdou lillah.',
    'Employer sa santé et son temps dans ce qui plaît à Allah.',
    'Remercier concrètement les personnes qui nous font du bien.',
    'Veiller à la prière à son heure.',
  ],
  'douas': [
    "Ô Allah, aide-nous à T'évoquer, à Te remercier et à T'adorer de la meilleure façon.",
  ],
};

class ClientDemo {
  Future<String> transcrire() async {
    await Future.delayed(const Duration(milliseconds: 1800));
    return _demoTranscription;
  }

  Future<String> generer({Map<String, dynamic>? schema, void Function(String)? onDelta}) async {
    if (schema != null) {
      await Future.delayed(const Duration(milliseconds: 1200));
      return jsonEncode(_demoSynthese);
    }
    final morceaux = _demoTraduction.split(RegExp(r'(?<=\. )'));
    final tampon = StringBuffer();
    for (final m in morceaux) {
      tampon.write(m);
      onDelta?.call(tampon.toString());
      await Future.delayed(const Duration(milliseconds: 60));
    }
    return _demoTraduction;
  }
}

extension _Premier<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
