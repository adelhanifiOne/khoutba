// Import d'un fichier audio ou vidéo déjà présent sur le téléphone.
//
// Deux sources, parce qu'elles ne donnent pas accès aux mêmes fichiers :
//  - l'app Fichiers (iCloud, « Sur mon iPhone », WhatsApp, dictaphone…)
//  - la galerie Photos, où atterrissent les vidéos filmées avec le téléphone
//    et que le sélecteur de fichiers d'iOS ne montre pas.
//
// Le fichier est recopié dans l'app : l'original peut ensuite être supprimé
// ou déplacé sans casser l'enregistrement. D'une vidéo, on ne garde que la
// piste sonore — voir extraction_audio.dart.

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:uuid/uuid.dart';

import 'enregistreur.dart' show titreParDefaut;
import 'extraction_audio.dart';
import 'modeles.dart';
import 'stockage.dart';

/// Formats acceptés par au moins un des services de transcription.
const extensionsAudio = ['m4a', 'mp3', 'wav', 'aac', 'ogg', 'oga', 'opus', 'flac', 'amr', 'caf', 'webm'];
const extensionsVideo = ['mp4', 'mov', 'm4v', '3gp', 'avi', 'mkv', 'webm', 'mpeg', 'mpg'];

class ErreurImport implements Exception {
  final String message;
  ErreurImport(this.message);
  @override
  String toString() => message;
}

/// Étapes annoncées pendant l'import, pour que l'attente ait un sens.
enum EtapeImport {
  extraction('Extraction de la piste audio…'),
  copie('Copie du fichier…');

  const EtapeImport(this.libelle);
  final String libelle;
}

class ResultatImport {
  final Enregistrement enregistrement;

  /// Vrai quand c'est une vidéo dont la piste sonore n'a pas pu être isolée :
  /// le fichier envoyé au service d'IA sera bien plus lourd, autant le dire.
  final bool videoEntiere;

  const ResultatImport(this.enregistrement, {this.videoEntiere = false});
}

String _extension(String chemin) {
  final nom = chemin.split('/').last;
  final i = nom.lastIndexOf('.');
  return i > 0 ? nom.substring(i + 1).toLowerCase() : '';
}

bool estVideo(String chemin) => extensionsVideo.contains(_extension(chemin));

/// Ouvre l'app Fichiers et renvoie le fichier choisi, ou null si annulé.
Future<XFile?> choisirDansFichiers() async {
  const groupe = XTypeGroup(
    label: 'Audio et vidéo',
    extensions: [...extensionsAudio, ...extensionsVideo],
    mimeTypes: ['audio/*', 'video/*'],          // Android
    uniformTypeIdentifiers: ['public.audio', 'public.movie'], // iOS
  );
  return openFile(acceptedTypeGroups: const [groupe]);
}

/// Ouvre la galerie et renvoie la vidéo choisie, ou null si annulé.
Future<XFile?> choisirVideoGalerie() =>
    ImagePicker().pickVideo(source: ImageSource.gallery);

/// Range le fichier choisi dans l'app et crée la fiche correspondante.
///
/// Pour une vidéo, seule la piste sonore est conservée : l'image ne sert à
/// rien pour une transcription, et fait passer le fichier de ~700 Mo à ~10.
Future<ResultatImport> importer(
  XFile fichier, {
  void Function(EtapeImport etape, double? progression)? onProgression,
}) async {
  final source = File(fichier.path);
  if (!await source.exists()) {
    throw ErreurImport('Fichier introuvable — il a peut-être été déplacé.');
  }
  final taille = await source.length();
  if (taille < 1024) {
    throw ErreurImport('Fichier vide ou illisible.');
  }

  var ext = _extension(fichier.name.isNotEmpty ? fichier.name : fichier.path);
  if (ext.isEmpty) ext = 'm4a';
  if (!extensionsAudio.contains(ext) && !extensionsVideo.contains(ext)) {
    throw ErreurImport(
      'Format « .$ext » non pris en charge. Formats acceptés : '
      'audio (m4a, mp3, wav…) ou vidéo (mp4, mov…).',
    );
  }

  final id = const Uuid().v4();
  final dossier = (await Stockage.dossierAudio()).path;
  String destination;
  var videoEntiere = false;

  if (extensionsVideo.contains(ext)) {
    onProgression?.call(EtapeImport.extraction, 0);
    final extrait = await extraireAudio(
      source.path,
      '$dossier/$id.m4a',
      onProgression: (p) => onProgression?.call(EtapeImport.extraction, p),
    );
    if (extrait != null) {
      destination = extrait.path;
    } else {
      // Le système n'a pas su isoler la piste : on garde la vidéo entière.
      videoEntiere = true;
      destination = '$dossier/$id.$ext';
      onProgression?.call(EtapeImport.copie, null);
      await source.copy(destination);
    }
  } else {
    destination = '$dossier/$id.$ext';
    onProgression?.call(EtapeImport.copie, null);
    await source.copy(destination);
  }

  // Titre : le nom du fichier s'il est parlant, sinon la date.
  var titre = fichier.name.replaceFirst(RegExp(r'\.[^.]+$'), '').trim();
  final anonyme = titre.isEmpty ||
      RegExp(r'^(IMG|VID|AUD|PXL|MOV|video|audio)[-_ ]?\d*$', caseSensitive: false).hasMatch(titre);
  if (anonyme) titre = titreParDefaut(DateTime.now());

  final rec = Enregistrement(
    id: id,
    titre: titre,
    titrePerso: !anonyme,
    creeLe: await _dateDuFichier(source),
    cheminAudio: destination,
    dureeSecondes: await _duree(destination),
  );
  await Stockage.sauver(rec);
  return ResultatImport(rec, videoEntiere: videoEntiere);
}

/// Date de dernière modification du fichier : plus juste que « maintenant »
/// pour un enregistrement fait la semaine précédente.
Future<DateTime> _dateDuFichier(File f) async {
  try {
    final d = await f.lastModified();
    // Une date aberrante (avant 2000, ou dans le futur) est ignorée.
    if (d.year >= 2000 && d.isBefore(DateTime.now().add(const Duration(days: 1)))) {
      return d;
    }
  } catch (_) {}
  return DateTime.now();
}

/// Durée réelle du média, lue par le lecteur du système (gère aussi la vidéo).
Future<int> _duree(String chemin) async {
  final lecteur = AudioPlayer();
  try {
    final d = await lecteur.setFilePath(chemin);
    return d?.inSeconds ?? 0;
  } catch (_) {
    return 0; // durée inconnue : sans conséquence, elle sera relue à l'ouverture
  } finally {
    await lecteur.dispose();
  }
}
