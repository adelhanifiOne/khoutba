// La khoutba d'exemple, celle que montre « Voir un exemple ».
//
// Le bouton promettait un exemple et n'activait que le mode démo : on
// retombait sur l'écran d'accueil, vide, avec « Aucun enregistrement pour
// l'instant ». C'était le premier écran de quiconque découvre l'app — testeur
// de l'App Store compris, à qui l'on demandait de juger sur une liste vide.
//
// La fiche est donc créée déjà traitée, avec le contenu fictif du mode démo :
// on voit immédiatement ce que l'app produit, sans clé et sans attendre.

import 'fournisseurs.dart';
import 'modeles.dart';
import 'stockage.dart';

/// Identifiant fixe : relancer « Voir un exemple » ne crée pas de doublon.
const idExemple = 'exemple-khoutba';

/// Durée d'une khoutba ordinaire. Aucun fichier audio n'accompagne l'exemple
/// — le lecteur se masque tout seul — mais la durée affichée doit rester
/// crédible dans la liste.
const _dureeExemple = 1524; // 25:24

Future<Enregistrement> creerExemple() async {
  for (final e in await Stockage.lister()) {
    if (e.id == idExemple) return e;
  }

  final rec = Enregistrement(
    id: idExemple,
    titre: demoSynthese['titre'].toString(),
    titrePerso: true,
    creeLe: dernierVendredi(),
    cheminAudio: '', // pas de fichier : la fiche n'en a pas besoin
    dureeSecondes: _dureeExemple,
  )
    ..transcription = demoTranscription
    ..traduction = demoTraduction
    ..synthese = Synthese.depuisJson(Map<String, dynamic>.from(demoSynthese))
    ..statut = Statut.termine;

  await Stockage.sauver(rec);
  return rec;
}

/// Le vendredi le plus récent, aujourd'hui compris : une khoutba datée d'un
/// mardi se remarquerait tout de suite.
DateTime dernierVendredi([DateTime? maintenant]) {
  final n = maintenant ?? DateTime.now();
  final recul = (n.weekday - DateTime.friday + 7) % 7;
  final jour = DateTime(n.year, n.month, n.day).subtract(Duration(days: recul));
  return jour.add(const Duration(hours: 13, minutes: 5)); // après la prière
}
