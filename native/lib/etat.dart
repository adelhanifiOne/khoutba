// État global de l'application, partagé par les écrans.

import 'package:flutter/foundation.dart';

import 'enregistreur.dart';
import 'modeles.dart';
import 'reglages.dart';
import 'stockage.dart';
import 'traitement.dart';

class EtatApp extends ChangeNotifier {
  static final EtatApp instance = EtatApp._();
  EtatApp._();

  final Reglages reglages = Reglages();
  final Enregistreur enregistreur = Enregistreur();

  List<Enregistrement> enregistrements = [];
  bool chargement = true;

  /// Traitement en cours : identifiant de la fiche + avancement.
  String? idEnTraitement;
  AvancementTraitement? avancement;

  Future<void> initialiser() async {
    await reglages.charger();
    final recupere = await Enregistreur.recupererSessionInterrompue();
    await rafraichir();
    chargement = false;
    if (recupere != null) messageRecuperation = recupere.id;
    notifyListeners();
  }

  /// Renseigné une seule fois si un enregistrement interrompu a été récupéré.
  String? messageRecuperation;

  Future<void> rafraichir() async {
    enregistrements = await Stockage.lister();
    // Un statut « en cours » survivant à une fermeture est ramené à un état
    // stable, pour ne pas afficher une progression figée.
    for (final rec in enregistrements) {
      final stable = rec.statutStable;
      if (stable != rec.statut) {
        rec.statut = stable;
        await Stockage.sauver(rec);
      }
    }
    notifyListeners();
  }

  Enregistrement? parId(String id) {
    for (final e in enregistrements) {
      if (e.id == id) return e;
    }
    return null;
  }

  Future<void> supprimer(Enregistrement rec) async {
    await Stockage.supprimer(rec);
    await rafraichir();
  }

  Future<void> sauver(Enregistrement rec) async {
    await Stockage.sauver(rec);
    notifyListeners();
  }

  /// Lance le traitement IA d'un enregistrement (transcription → traduction →
  /// synthèse) en tenant l'interface informée.
  Future<void> traiter(Enregistrement rec, {bool forcer = false}) async {
    idEnTraitement = rec.id;
    avancement = const AvancementTraitement(Phase.transcription);
    notifyListeners();
    try {
      await Traitement.lancer(
        rec,
        reglages,
        forcer: forcer,
        onAvancement: (a) {
          avancement = a;
          notifyListeners();
        },
      );
    } finally {
      idEnTraitement = null;
      avancement = null;
      await rafraichir();
    }
  }

  bool estEnTraitement(Enregistrement rec) => idEnTraitement == rec.id;
}
