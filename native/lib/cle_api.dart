// Aide à l'obtention d'une clé API.
//
// C'est l'étape qui décide de tout pour un nouvel utilisateur : « va créer une
// clé sur aistudio.google.com » suffit à en perdre la plupart. On ouvre donc la
// bonne page d'un bouton, et on rattrape les collages manifestement ratés.
//
// Leçon apprise à nos dépens : le contrôle ne doit **jamais** reposer sur le
// préfixe attendu. Les clés Gemini ont commencé par « AIza », puis Google est
// passé à « AQ. » — et la vérification, censée aider, refusait alors des clés
// parfaitement valides. On ne bloque donc que sur ce qui est certainement
// faux ; le reste part au service, seul juge légitime.

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const urlCleGemini = 'https://aistudio.google.com/apikey';
const urlCleOpenAI = 'https://platform.openai.com/api-keys';
const urlCleClaude = 'https://console.anthropic.com/settings/keys';

String urlCle(String fournisseur) => switch (fournisseur) {
      'openai' => urlCleOpenAI,
      'anthropic' => urlCleClaude,
      _ => urlCleGemini,
    };

/// Préfixes connus, à titre indicatif seulement : ils servent à *signaler* une
/// clé qui semble venir d'un autre service, jamais à en refuser une.
const _prefixesConnus = {
  'gemini': ['AIza', 'AQ.'],
  'openai': ['sk-'],
  'anthropic': ['sk-ant-'],
};

/// Vrai si la chaîne peut être une clé. Ne dit pas qu'elle est valide — le
/// service seul le sait — seulement qu'elle vaut la peine d'être essayée.
///
/// Refuse uniquement ce qui ne peut pas en être une : un champ vide, une
/// adresse e-mail ou une URL collée par erreur, et surtout une clé **tronquée
/// par les points de suspension** de l'affichage Google, où la clé n'apparaît
/// qu'abrégée, terminée par des points de suspension : recopier ce qui est à
/// l'écran au lieu d'utiliser le bouton Copier est l'erreur la plus fréquente.
bool clePlausible(String fournisseur, String valeur) {
  final v = valeur.trim();
  if (v.length < 20) return false;
  if (v.contains(RegExp(r'\s'))) return false;
  if (v.contains('…') || v.contains('...')) return false; // copie abrégée
  if (v.contains('@')) return false; // adresse e-mail
  if (v.startsWith('http')) return false; // l'adresse de la page, pas la clé
  return true;
}

/// Vrai si la clé ne ressemble à aucun format connu pour ce service : de quoi
/// afficher un avertissement — sans bloquer, puisque les formats changent.
bool cleInattendue(String fournisseur, String valeur) {
  final v = valeur.trim();
  if (v.isEmpty) return false;
  final prefixes = _prefixesConnus[fournisseur];
  if (prefixes == null) return false;
  return !prefixes.any(v.startsWith);
}

/// Ouvre la page de création de clé dans le navigateur.
/// Renvoie faux si le système refuse — l'appelant affiche alors l'adresse.
Future<bool> ouvrirPageCle(String fournisseur) async {
  try {
    return await launchUrl(
      Uri.parse(urlCle(fournisseur)),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}

/// Contenu texte du presse-papiers, vide s'il est inaccessible ou vide.
Future<String> pressePapiers() async {
  try {
    return (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim() ?? '';
  } catch (_) {
    return '';
  }
}
