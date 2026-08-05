// Stockage local : métadonnées dans un JSON, audio dans des fichiers .m4a.
// Rien ne quitte le téléphone, sauf au moment du traitement par l'IA.

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'modeles.dart';

/// Sur iOS, un même fichier s'écrit `/var/…` ou `/private/var/…` selon qui
/// donne le chemin. Sans cette normalisation, un fichier bien référencé passe
/// pour un orphelin — et se fait effacer.
String cheminNormalise(String chemin) =>
    chemin.startsWith('/private/') ? chemin.substring(8) : chemin;

class Stockage {
  static Directory? _dossier;

  static Future<Directory> dossier() async =>
      _dossier ??= await getApplicationDocumentsDirectory();

  static Future<Directory> dossierTemporaire() => getTemporaryDirectory();

  /// Vrai si le fichier est une copie fabriquée par le sélecteur dans le
  /// dossier temporaire de l'app : le supprimer ne fait rien perdre à
  /// l'utilisateur, contrairement à un fichier choisi dans iCloud.
  static Future<bool> estTemporaire(String chemin) async {
    final tmp = cheminNormalise((await dossierTemporaire()).path);
    return cheminNormalise(chemin).startsWith('$tmp/');
  }

  static Future<Directory> dossierAudio() async {
    final d = Directory('${(await dossier()).path}/audio');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<File> _fichierIndex() async =>
      File('${(await dossier()).path}/enregistrements.json');

  static Future<List<Enregistrement>> lister() async {
    final f = await _fichierIndex();
    if (!await f.exists()) return [];
    try {
      final data = jsonDecode(await f.readAsString());
      if (data is! List) return [];
      final liste = data
          .whereType<Map>()
          .map((e) => Enregistrement.depuisJson(Map<String, dynamic>.from(e)))
          .toList();
      liste.sort((a, b) => b.creeLe.compareTo(a.creeLe)); // le plus récent d'abord
      return liste;
    } catch (_) {
      return []; // index illisible : on repart proprement plutôt que planter
    }
  }

  static Future<void> _ecrireTout(List<Enregistrement> liste) async {
    final f = await _fichierIndex();
    final temporaire = File('${f.path}.tmp');
    // Écriture puis renommage : l'index n'est jamais laissé à moitié écrit.
    await temporaire.writeAsString(jsonEncode(liste.map((e) => e.versJson()).toList()));
    await temporaire.rename(f.path);
  }

  static Future<void> sauver(Enregistrement rec) async {
    final liste = await lister();
    final i = liste.indexWhere((e) => e.id == rec.id);
    if (i >= 0) {
      liste[i] = rec;
    } else {
      liste.add(rec);
    }
    await _ecrireTout(liste);
  }

  static Future<void> supprimer(Enregistrement rec) async {
    final liste = await lister();
    liste.removeWhere((e) => e.id == rec.id);
    await _ecrireTout(liste);
    final f = File(rec.cheminAudio);
    if (await f.exists()) await f.delete();
  }

  static Future<void> toutSupprimer() async {
    for (final rec in await lister()) {
      final f = File(rec.cheminAudio);
      if (await f.exists()) await f.delete();
    }
    await _ecrireTout([]);
  }

  /// Ménage au lancement : efface les fichiers audio que plus aucune fiche ne
  /// référence (import interrompu, extraction abandonnée, copie tronquée) et
  /// les doublons laissés par les sélecteurs de fichiers dans le temporaire.
  /// Un import de vidéo raté laisse sinon des centaines de mégaoctets pris,
  /// invisibles dans l'app comme dans les réglages de l'iPhone.
  ///
  /// À n'appeler qu'au démarrage, après la récupération d'une session
  /// interrompue : avant, le fichier récupéré passerait pour un orphelin.
  /// Renvoie le nombre d'octets rendus au téléphone.
  static Future<int> menageDemarrage() async {
    var rendus = 0;
    final connus = {for (final e in await lister()) cheminNormalise(e.cheminAudio)};
    try {
      await for (final e in (await dossierAudio()).list()) {
        if (e is File && !connus.contains(cheminNormalise(e.path))) {
          rendus += await _effacer(e);
        }
      }
    } catch (_) {}
    try {
      await for (final e in (await dossierTemporaire()).list()) {
        if (e is File) rendus += await _effacer(e);
      }
    } catch (_) {}
    return rendus;
  }

  static Future<int> _effacer(File f) async {
    try {
      final taille = await f.length();
      await f.delete();
      return taille;
    } catch (_) {
      return 0;
    }
  }

  /// Taille totale occupée par les enregistrements, en octets.
  static Future<int> tailleUtilisee() async {
    var total = 0;
    final d = await dossierAudio();
    await for (final e in d.list()) {
      if (e is File) total += await e.length();
    }
    return total;
  }
}
