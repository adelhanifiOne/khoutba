// Comment obtenir une clé Gemini, en images.
//
// Le texte seul ne suffisait pas. Entre l'app et Google AI Studio, le parcours
// traverse quatre écrans inconnus, dans une interface en anglais par endroits,
// et se termine par une boîte iOS que personne n'attend — « Khoutba souhaite
// coller un élément depuis Safari ». Refuser là, et la clé n'arrive jamais
// sans qu'on comprenne pourquoi.
//
// Les captures sont recadrées autour de l'élément à toucher : une capture de
// téléphone entière, réduite à la largeur d'une colonne, ne se lit pas.
//
// Replié par défaut : celui qui sait faire n'a pas à dérouler sept étapes, et
// l'écran de saisie reste court sur un petit téléphone.

import 'package:flutter/material.dart';

import '../theme.dart';

class EtapeCle {
  const EtapeCle(this.texte, {this.image});

  final String texte;

  /// Capture illustrant l'étape. Absente quand il n'y en a pas — l'étape
  /// reste affichée, car son texte compte autant que les autres.
  final String? image;
}

const etapesCle = <EtapeCle>[
  EtapeCle('Appuie sur « Ouvrir la page Google » ci-dessus.',
      image: 'assets/tuto/1.jpg'),
  EtapeCle('Sur la page de Google, appuie sur « Créer une clé API », en haut à droite.',
      image: 'assets/tuto/2.jpg'),
  EtapeCle('Laisse le projet proposé tel quel, puis appuie sur « Créer une clé ».',
      image: 'assets/tuto/3.jpg'),
  EtapeCle('La clé apparaît. Appuie sur l’icône de copie, à sa droite.',
      image: 'assets/tuto/4.jpg'),
  EtapeCle('Reviens dans Khoutba et appuie sur l’icône de collage, dans le champ.',
      image: 'assets/tuto/5.jpg'),
  EtapeCle('iOS demande l’autorisation de coller : appuie sur « Autoriser le collage ».'),
  EtapeCle('La clé s’inscrit dans le champ. Appuie sur « Terminer », c’est fini.'),
];

class TutoCle extends StatefulWidget {
  const TutoCle({super.key});

  @override
  State<TutoCle> createState() => _TutoCleState();
}

class _TutoCleState extends State<TutoCle> {
  bool _ouvert = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 4)),
            onPressed: () => setState(() => _ouvert = !_ouvert),
            icon: Icon(_ouvert ? Icons.expand_less : Icons.expand_more, size: 20),
            label: Text(_ouvert ? 'Masquer les étapes' : 'Voir les étapes en images'),
          ),
        ),
        if (_ouvert)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < etapesCle.length; i++)
                  _EtapeVue(numero: i + 1, etape: etapesCle[i]),
              ],
            ),
          ),
      ],
    );
  }
}

class _EtapeVue extends StatelessWidget {
  const _EtapeVue({required this.numero, required this.etape});

  final int numero;
  final EtapeCle etape;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 22,
                height: 22,
                margin: const EdgeInsets.only(right: 10, top: 1),
                decoration: BoxDecoration(
                  color: accentTexte(context).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$numero',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accentTexte(context),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  etape.texte,
                  style: TextStyle(fontSize: 14, height: 1.45, color: theme.hintColor),
                ),
              ),
            ],
          ),
          if (etape.image != null) ...[
            const SizedBox(height: 10),
            Padding(
              // Aligné sur le texte, pas sur la pastille : l'image appartient
              // à l'étape, elle n'en est pas le titre.
              padding: const EdgeInsets.only(left: 32),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  etape.image!,
                  fit: BoxFit.fitWidth,
                  width: double.infinity,
                  // Une capture manquante ne doit pas casser l'écran de
                  // saisie : l'étape reste lisible sans son illustration.
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
