// Structures de données de l'application.

enum Statut { pret, transcription, transcrit, traduction, traduit, synthese, termine, erreur }

Statut statutDepuisTexte(String? s) =>
    Statut.values.firstWhere((e) => e.name == s, orElse: () => Statut.pret);

class Citation {
  final String type; // coran | hadith | autre
  final String texteArabe;
  final String traduction;
  final String reference;

  const Citation({
    required this.type,
    required this.texteArabe,
    required this.traduction,
    required this.reference,
  });

  factory Citation.depuisJson(Map<String, dynamic> j) => Citation(
        type: (j['type'] ?? 'autre').toString(),
        texteArabe: (j['texte_arabe'] ?? '').toString(),
        traduction: (j['traduction'] ?? '').toString(),
        reference: (j['reference'] ?? '').toString(),
      );

  Map<String, dynamic> versJson() => {
        'type': type,
        'texte_arabe': texteArabe,
        'traduction': traduction,
        'reference': reference,
      };
}

class Synthese {
  final String titre;
  final String theme;
  final String resume;
  final List<String> pointsCles;
  final List<Citation> citations;
  final List<String> conseils;
  final List<String> douas;

  const Synthese({
    required this.titre,
    required this.theme,
    required this.resume,
    required this.pointsCles,
    required this.citations,
    required this.conseils,
    required this.douas,
  });

  static List<String> _listeTexte(dynamic v) =>
      (v is List) ? v.map((e) => e.toString()).toList() : <String>[];

  factory Synthese.depuisJson(Map<String, dynamic> j) => Synthese(
        titre: (j['titre'] ?? '').toString(),
        theme: (j['theme'] ?? '').toString(),
        resume: (j['resume'] ?? '').toString(),
        pointsCles: _listeTexte(j['points_cles']),
        citations: (j['citations'] is List)
            ? (j['citations'] as List)
                .whereType<Map>()
                .map((e) => Citation.depuisJson(Map<String, dynamic>.from(e)))
                .toList()
            : <Citation>[],
        conseils: _listeTexte(j['conseils']),
        douas: _listeTexte(j['douas']),
      );

  Map<String, dynamic> versJson() => {
        'titre': titre,
        'theme': theme,
        'resume': resume,
        'points_cles': pointsCles,
        'citations': citations.map((c) => c.versJson()).toList(),
        'conseils': conseils,
        'douas': douas,
      };
}

class Enregistrement {
  final String id;
  String titre;
  bool titrePerso;
  final DateTime creeLe;
  int dureeSecondes;
  String cheminAudio; // chemin absolu du fichier .m4a
  Statut statut;
  String? transcription;
  String? traduction;
  Synthese? synthese;
  String? erreur;

  Enregistrement({
    required this.id,
    required this.titre,
    required this.creeLe,
    required this.cheminAudio,
    this.titrePerso = false,
    this.dureeSecondes = 0,
    this.statut = Statut.pret,
    this.transcription,
    this.traduction,
    this.synthese,
    this.erreur,
  });

  factory Enregistrement.depuisJson(Map<String, dynamic> j) => Enregistrement(
        id: j['id'].toString(),
        titre: (j['titre'] ?? '').toString(),
        titrePerso: j['titrePerso'] == true,
        creeLe: DateTime.tryParse((j['creeLe'] ?? '').toString()) ?? DateTime.now(),
        dureeSecondes: (j['dureeSecondes'] as num?)?.toInt() ?? 0,
        cheminAudio: (j['cheminAudio'] ?? '').toString(),
        statut: statutDepuisTexte(j['statut']?.toString()),
        transcription: j['transcription']?.toString(),
        traduction: j['traduction']?.toString(),
        synthese: (j['synthese'] is Map)
            ? Synthese.depuisJson(Map<String, dynamic>.from(j['synthese']))
            : null,
        erreur: j['erreur']?.toString(),
      );

  Map<String, dynamic> versJson() => {
        'id': id,
        'titre': titre,
        'titrePerso': titrePerso,
        'creeLe': creeLe.toIso8601String(),
        'dureeSecondes': dureeSecondes,
        'cheminAudio': cheminAudio,
        'statut': statut.name,
        'transcription': transcription,
        'traduction': traduction,
        'synthese': synthese?.versJson(),
        'erreur': erreur,
      };

  /// Ramène un statut « en cours » à un état stable, après une fermeture
  /// de l'app pendant un traitement.
  Statut get statutStable {
    switch (statut) {
      case Statut.transcription:
        return transcription != null ? Statut.transcrit : Statut.pret;
      case Statut.traduction:
        return traduction != null ? Statut.traduit : Statut.transcrit;
      case Statut.synthese:
        return Statut.traduit;
      default:
        return statut;
    }
  }
}
