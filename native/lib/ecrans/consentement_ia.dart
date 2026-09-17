// Écran d'accord avant tout envoi vers un service d'IA.
//
// Apple exige quatre choses (5.1.1(i) et 5.1.2(i)) : dire ce qui est envoyé,
// nommer le destinataire, obtenir l'accord avant l'envoi, et reprendre tout
// cela dans la politique de confidentialité. Les trois premières se jouent
// ici ; la quatrième dans privacy.html.
//
// Volontairement un écran plein et non une alerte : il y a trop à lire pour
// une boîte de dialogue, et un écran qu'on doit traverser se remarque — y
// compris par le testeur d'Apple.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../consentement.dart';
import '../reglages.dart';
import '../theme.dart';

/// Demande l'accord d'envoi et le mémorise. Renvoie vrai si l'utilisateur
/// accepte ; dans ce cas seulement, l'appelant peut lancer le traitement.
///
/// [destinatairesForces] sert à l'accueil, où le service n'est pas encore
/// inscrit dans les réglages mais où l'on sait déjà lequel ce sera.
/// [memoriser] est faux quand l'appelant enregistrera l'accord lui-même, une
/// fois les réglages en place — sinon la signature mémorisée serait celle
/// d'une configuration vide.
Future<bool> demanderConsentementIA(
  BuildContext context,
  Reglages reglages, {
  List<DestinataireIA>? destinatairesForces,
  bool memoriser = true,
}) async {
  final accepte = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => EcranConsentementIA(
        reglages: reglages,
        destinatairesForces: destinatairesForces,
      ),
    ),
  );
  if (accepte != true) return false;
  if (memoriser) await reglages.accorderConsentementIA();
  return true;
}

/// Même écran, en lecture seule, pour relire l'accord depuis les réglages.
Future<void> revoirConsentementIA(BuildContext context, Reglages reglages) {
  return Navigator.push<void>(
    context,
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => EcranConsentementIA(reglages: reglages, lectureSeule: true),
    ),
  );
}

class EcranConsentementIA extends StatelessWidget {
  const EcranConsentementIA({
    super.key,
    required this.reglages,
    this.lectureSeule = false,
    this.destinatairesForces,
  });

  final Reglages reglages;
  final bool lectureSeule;

  /// Destinataires à annoncer quand les réglages ne les portent pas encore.
  final List<DestinataireIA>? destinatairesForces;

  Future<void> _ouvrir(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      // Le système refuse d'ouvrir le lien : l'adresse reste affichée à l'écran.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final destinataires = destinatairesForces ?? reglages.destinatairesIA;
    final demo = reglages.demo && destinatairesForces == null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Envoi à un service d’IA'),
        automaticallyImplyLeading: lectureSeule,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            if (demo) _encartDemo(context),
            Text(
              'Pour transcrire, traduire et résumer un prêche, Khoutba doit '
              'confier votre enregistrement à un service d’intelligence '
              'artificielle. Voici exactement ce qui part, et chez qui.',
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
            const SizedBox(height: 24),

            _titre(context, 'Ce qui est envoyé'),
            _puce(context, 'L’enregistrement audio du prêche concerné — celui-là seul.'),
            _puce(context, 'Le texte arabe issu de la transcription, pour la traduction et le résumé.'),
            _puce(context, 'Votre clé API, qui vous identifie auprès du service et lui est destinée.'),
            const SizedBox(height: 16),

            _titre(context, 'Ce qui n’est jamais envoyé'),
            _puce(context, 'Aucun nom, aucune adresse e-mail, aucun compte : Khoutba n’en demande pas.'),
            _puce(context, 'Aucun identifiant d’appareil, aucune position, aucune statistique d’usage.'),
            _puce(context, 'Vos autres enregistrements, qui restent sur le téléphone.'),
            _puce(context, 'Rien vers l’auteur de Khoutba, qui n’a aucun serveur.'),
            const SizedBox(height: 24),

            _titre(context, demo ? 'À qui, une fois configuré' : 'À qui'),
            if (destinataires.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Au service que vous choisirez dans les réglages : Google Gemini '
                  '(Google LLC), OpenAI (OpenAI, L.L.C.) ou Claude (Anthropic PBC). '
                  'Son nom sera rappelé ici avant le premier envoi.',
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                ),
              )
            else
              ...destinataires.asMap().entries.map(
                    (e) => _carteDestinataire(context, e.value, destinataires, e.key),
                  ),
            const SizedBox(height: 24),

            _titre(context, 'Ce qu’ils en font'),
            Text(
              'Ces sociétés traitent l’envoi pour produire le texte, selon leurs '
              'propres conditions. Les offres gratuites, celle de Gemini comprise, '
              'permettent en général au service de conserver le contenu et de '
              's’en servir pour améliorer ses modèles, avec une relecture humaine '
              'possible. N’envoyez donc pas un enregistrement dont le contenu '
              'doit rester confidentiel.',
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
            const SizedBox(height: 12),
            TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () => _ouvrir(urlPolitiqueKhoutba),
              child: const Text('Lire la politique de confidentialité de Khoutba'),
            ),
            const SizedBox(height: 24),

            if (lectureSeule)
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fermer'),
              )
            else ...[
              Text(
                'Rien n’a encore été envoyé. Aucun envoi n’a lieu tant que vous '
                'n’avez pas accepté, et vous pourrez revenir sur cet accord à '
                'tout moment depuis les réglages.',
                style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(demo ? 'J’ai compris, continuer' : 'J’accepte l’envoi'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Ne pas envoyer'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _encartDemo(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: orLisible(context).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Mode démo : rien ne quitte votre téléphone, les textes affichés sont '
        'fictifs. Cet écran est celui qui s’affiche avant tout envoi réel.',
        style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
      ),
    );
  }

  Widget _titre(BuildContext context, String texte) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          texte,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: accentTexte(context), fontWeight: FontWeight.w700),
        ),
      );

  Widget _puce(BuildContext context, String texte) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 10),
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(color: orLisible(context), shape: BoxShape.circle),
              ),
            ),
            Expanded(
              child: Text(
                texte,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4),
              ),
            ),
          ],
        ),
      );

  Widget _carteDestinataire(
    BuildContext context,
    DestinataireIA d,
    List<DestinataireIA> tous,
    int rang,
  ) {
    final theme = Theme.of(context);
    // Hors réglages établis — à l'accueil — les rôles se déduisent de l'ordre :
    // le premier transcrit, le dernier rédige, et un service seul fait les deux.
    final bool transcrit;
    final bool redige;
    if (destinatairesForces == null) {
      transcrit = reglages.stt == d.id;
      redige = reglages.llm == d.id;
    } else {
      transcrit = rang == 0;
      redige = rang == tous.length - 1;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(d.service, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('Société : ${d.societe}', style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          Text(
            'Reçoit ${cequilRecoit(transcrit: transcrit, redige: redige)}.',
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
          ),
          const SizedBox(height: 6),
          TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
            onPressed: () => _ouvrir(d.politique),
            child: Text('Sa politique de confidentialité', style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

const urlPolitiqueKhoutba = 'https://adelhanifione.github.io/khoutba/privacy.html';
