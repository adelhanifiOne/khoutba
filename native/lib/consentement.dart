// Ce que Khoutba envoie, à qui, et l'accord de l'utilisateur avant l'envoi.
//
// Apple a refusé la version 1.0 (3) au titre des règles 5.1.1(i) et 5.1.2(i) :
// une app qui confie des données personnelles à un service d'IA tiers doit
// dire ce qu'elle envoie, nommer précisément le destinataire, et obtenir un
// accord *avant* l'envoi. Le testeur l'a écrit noir sur blanc : le mentionner
// dans la politique de confidentialité ne suffit pas, l'accord se demande
// dans l'application.
//
// D'où ce fichier, qui tient le catalogue des destinataires possibles et la
// règle de validité de l'accord. L'accord porte sur un jeu de destinataires
// précis : changer de service dans les réglages invalide l'accord donné pour
// l'ancien, puisque ce n'est plus la même société qui reçoit l'audio.

/// Un service d'IA susceptible de recevoir les données, nommé sans ambiguïté.
class DestinataireIA {
  const DestinataireIA({
    required this.id,
    required this.service,
    required this.societe,
    required this.politique,
  });

  /// Identifiant interne : gemini | openai | anthropic.
  final String id;

  /// Nom commercial du service, tel que l'utilisateur le voit dans les réglages.
  final String service;

  /// Raison sociale de l'entreprise qui reçoit réellement les données.
  final String societe;

  /// Politique de confidentialité du service, à ouvrir depuis l'écran d'accord.
  final String politique;

  String get libelle => '$service — $societe';
}

const destinatairesConnus = <String, DestinataireIA>{
  'gemini': DestinataireIA(
    id: 'gemini',
    service: 'Google Gemini',
    societe: 'Google LLC',
    politique: 'https://ai.google.dev/gemini-api/terms',
  ),
  'openai': DestinataireIA(
    id: 'openai',
    service: 'OpenAI',
    societe: 'OpenAI, L.L.C.',
    politique: 'https://openai.com/policies/privacy-policy/',
  ),
  'anthropic': DestinataireIA(
    id: 'anthropic',
    service: 'Claude',
    societe: 'Anthropic PBC',
    politique: 'https://www.anthropic.com/legal/privacy',
  ),
};

/// Ce qu'un destinataire reçoit, selon le rôle qu'on lui a confié.
///
/// La distinction compte pour l'utilisateur : Claude ne reçoit jamais d'audio,
/// seulement le texte déjà transcrit. Annoncer « l'audio part chez Anthropic »
/// serait faux, et l'imprécision est précisément ce qu'Apple reproche.
String cequilRecoit({required bool transcrit, required bool redige}) {
  if (transcrit && redige) return "l'enregistrement audio, puis le texte transcrit";
  if (transcrit) return "l'enregistrement audio";
  return 'le texte arabe transcrit';
}

/// Destinataires réellement concernés, dans l'ordre où ils interviennent.
///
/// [stt] transcrit l'audio, [llm] traduit et résume le texte. Quand les deux
/// pointent sur le même service, il n'apparaît qu'une fois.
List<DestinataireIA> destinatairesPour(String stt, String llm) {
  final ids = <String>[
    if (stt.isNotEmpty) stt,
    if (llm.isNotEmpty && llm != stt) llm,
  ];
  return [
    for (final id in ids)
      if (destinatairesConnus[id] != null) destinatairesConnus[id]!,
  ];
}

/// Empreinte stable du jeu de destinataires, telle qu'elle est mémorisée.
///
/// Triée pour qu'un même couple de services donne toujours la même chaîne, quel
/// que soit l'ordre dans lequel l'utilisateur a rempli les réglages.
String signatureDestinataires(Iterable<String> ids) {
  final tries = ids.toSet().toList()..sort();
  return tries.join('+');
}
