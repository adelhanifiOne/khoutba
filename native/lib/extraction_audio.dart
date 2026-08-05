// Extraction de la piste sonore d'une vidéo, avant tout envoi.
//
// Une khoutba de 11 min filmée avec le téléphone pèse ~700 Mo ; sa piste
// sonore seule, une dizaine de Mo. Envoyer la vidéo entière, c'est un quart
// d'heure d'attente, un forfait data entamé, et souvent un échec — alors que
// l'image ne sert à rien : seul le son est transcrit.
//
// Le découpage est fait par le système, sans dépendance :
//  - iOS     : AVAssetExportSession (preset Apple M4A)
//  - Android : MediaExtractor + MediaMuxer — la piste est recopiée telle
//              quelle, sans ré-encodage, donc sans perte ni attente.
//
// Si la plateforme n'y arrive pas (codec inhabituel, app compilée sans la
// partie native), on renvoie null : l'appelant enverra la vidéo entière.
// Plus lourd, mais ça marche — un import ne doit jamais échouer pour ça.

import 'dart:io';

import 'package:flutter/services.dart';

const canalExtraction = MethodChannel('khoutba/extraction');

class ErreurExtraction implements Exception {
  final String message;
  ErreurExtraction(this.message);
  @override
  String toString() => message;
}

/// Suivi de progression de l'extraction en cours (une seule à la fois).
void Function(double)? _suivi;
bool _handlerPose = false;

Future<dynamic> _recevoir(MethodCall appel) async {
  if (appel.method == 'progression' && _suivi != null) {
    final valeur = appel.arguments;
    if (valeur is num) _suivi!(valeur.toDouble().clamp(0.0, 1.0));
  }
  return null;
}

/// Écrit la piste audio de [source] dans [destination] (un `.m4a`).
///
/// Renvoie le fichier produit, ou `null` si l'extraction n'a pas pu se faire —
/// dans ce cas la vidéo d'origine reste utilisable telle quelle.
/// Lève [ErreurExtraction] si la vidéo n'a tout simplement pas de son :
/// inutile d'envoyer 700 Mo de silence à un service de transcription.
Future<File?> extraireAudio(
  String source,
  String destination, {
  void Function(double)? onProgression,
}) async {
  if (!_handlerPose) {
    canalExtraction.setMethodCallHandler(_recevoir);
    _handlerPose = true;
  }
  _suivi = onProgression;
  try {
    final chemin = await canalExtraction.invokeMethod<String>('extraire', {
      'source': source,
      'destination': destination,
    });
    if (chemin != null) {
      final fichier = File(chemin);
      if (await fichier.exists() && await fichier.length() > 1024) return fichier;
    }
  } on MissingPluginException {
    // Plateforme sans partie native (bureau, tests) : repli sur la vidéo.
  } on PlatformException catch (e) {
    if (e.code == 'sans_audio') {
      await _supprimer(destination);
      throw ErreurExtraction(
        'Cette vidéo ne contient aucune piste sonore : il n’y a rien à transcrire.',
      );
    }
    // Codec exotique, mémoire, fichier abîmé : repli sur la vidéo entière.
  } finally {
    _suivi = null;
  }
  await _supprimer(destination); // un fichier à moitié écrit ne sert à rien
  return null;
}

/// Octets libres sur le téléphone, ou `null` si la plateforme ne sait pas le
/// dire. Sert à refuser un import trop gros *avant* d'écrire : une copie qui
/// tombe à court de place laisse un fichier tronqué qui, lui, prend la place.
Future<int?> espaceLibre() async {
  try {
    final octets = await canalExtraction.invokeMethod<int>('espaceLibre');
    return (octets == null || octets < 0) ? null : octets;
  } catch (_) {
    return null;
  }
}

Future<void> _supprimer(String chemin) async {
  try {
    final f = File(chemin);
    if (await f.exists()) await f.delete();
  } catch (_) {}
}
