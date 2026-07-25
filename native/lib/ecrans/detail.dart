// Fiche d'une khoutba : lecture audio, traitement IA, résumé / traduction /
// texte arabe, export et partage.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';

import '../etat.dart';
import '../fournisseurs.dart';
import '../modeles.dart';
import '../stockage.dart';
import '../theme.dart';
import 'accueil.dart';
import 'reglages_ecran.dart';

class EcranDetail extends StatefulWidget {
  final String idEnregistrement;
  const EcranDetail({super.key, required this.idEnregistrement});

  @override
  State<EcranDetail> createState() => _EcranDetailState();
}

class _EcranDetailState extends State<EcranDetail> with SingleTickerProviderStateMixin {
  final etat = EtatApp.instance;
  final _lecteur = AudioPlayer();
  late final TabController _onglets = TabController(length: 3, vsync: this);
  late final TextEditingController _titre;
  bool _audioPret = false;

  Enregistrement? get rec => etat.parId(widget.idEnregistrement);

  @override
  void initState() {
    super.initState();
    _titre = TextEditingController(text: rec?.titre ?? '');
    _preparerAudio();
    final r = rec;
    if (r != null && r.synthese == null && r.traduction != null) _onglets.index = 1;
  }

  Future<void> _preparerAudio() async {
    final r = rec;
    if (r == null) return;
    try {
      final duree = await _lecteur.setFilePath(r.cheminAudio);
      _audioPret = true;
      // La durée réelle corrige celle estimée (utile pour un fichier récupéré).
      if (duree != null && (r.dureeSecondes == 0 || (duree.inSeconds - r.dureeSecondes).abs() > 2)) {
        r.dureeSecondes = duree.inSeconds;
        await Stockage.sauver(r);
      }
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _audioPret = false);
    }
  }

  @override
  void dispose() {
    _lecteur.dispose();
    _titre.dispose();
    _onglets.dispose();
    super.dispose();
  }

  void _message(String texte) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texte), duration: const Duration(seconds: 4)));
  }

  Future<void> _traiter() async {
    final r = rec;
    if (r == null) return;
    if (!etat.reglages.pretPourTraitement) {
      _message('Configure d’abord les services IA dans les réglages.');
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const EcranReglages()));
      if (mounted) setState(() {});
      return;
    }
    final forcer = r.statut == Statut.termine;
    if (forcer) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Relancer tout le traitement ?'),
          content: const Text('La transcription, la traduction et le résumé seront refaits.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Relancer')),
          ],
        ),
      );
      if (ok != true) return;
    }

    try {
      await etat.traiter(r, forcer: forcer);
      _message('Traitement terminé ✓');
      if (mounted && rec?.synthese != null) _onglets.index = 0;
    } on ErreurIA catch (e) {
      _message('Échec : ${e.message}');
    } catch (e) {
      _message('Échec : $e');
    }
    if (mounted) setState(() {});
  }

  Future<void> _supprimer() async {
    final r = rec;
    if (r == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Supprimer cet enregistrement ?'),
        content: const Text('L’audio et les textes seront effacés définitivement.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    await etat.supprimer(r);
    if (mounted) Navigator.pop(context);
  }

  String _markdown(Enregistrement r) {
    final s = r.synthese;
    final b = StringBuffer()
      ..writeln('# ${r.titre}')
      ..writeln()
      ..writeln('*${formaterDate(r.creeLe)} · ${formaterDuree(r.dureeSecondes)}*')
      ..writeln();
    if (s != null) {
      if (s.theme.isNotEmpty) b..writeln('**Thème :** ${s.theme}')..writeln();
      if (s.resume.isNotEmpty) b..writeln('## Résumé')..writeln()..writeln(s.resume)..writeln();
      if (s.pointsCles.isNotEmpty) {
        b.writeln('## Points clés');
        b.writeln();
        for (final p in s.pointsCles) {
          b.writeln('- $p');
        }
        b.writeln();
      }
      if (s.citations.isNotEmpty) {
        b.writeln('## Versets & hadiths cités');
        b.writeln();
        for (final c in s.citations) {
          b.writeln('> ${c.texteArabe}');
          b.writeln('>');
          b.writeln('> ${c.traduction}');
          b.writeln('> — *${c.reference}*');
          b.writeln();
        }
      }
      if (s.conseils.isNotEmpty) {
        b.writeln('## Conseils pratiques');
        b.writeln();
        for (final c in s.conseils) {
          b.writeln('- $c');
        }
        b.writeln();
      }
      if (s.douas.isNotEmpty) {
        b.writeln('## Douas');
        b.writeln();
        for (final d in s.douas) {
          b.writeln('- $d');
        }
        b.writeln();
      }
    }
    if (r.traduction != null) {
      b..writeln('## Traduction complète')..writeln()..writeln(r.traduction)..writeln();
    }
    if (r.transcription != null) {
      b..writeln('## النص العربي')..writeln()..writeln(r.transcription)..writeln();
    }
    return b.toString();
  }

  Future<void> _partager() async {
    final r = rec;
    if (r == null) return;
    final s = r.synthese;
    final texte = s != null
        ? '${r.titre}\n\n${s.theme}\n\n${s.resume}\n\n'
            'Points clés :\n${s.pointsCles.map((p) => '• $p').join('\n')}'
        : (r.traduction ?? '');
    if (texte.trim().isEmpty) return;
    await SharePlus.instance.share(ShareParams(text: texte, subject: r.titre));
  }

  Future<void> _exporter() async {
    final r = rec;
    if (r == null) return;
    final fichier = File('${(await Stockage.dossier()).path}/khoutba-'
        '${r.creeLe.toIso8601String().substring(0, 10)}.md');
    await fichier.writeAsString(_markdown(r));
    await SharePlus.instance.share(
      ShareParams(files: [XFile(fichier.path)], subject: r.titre),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: etat,
      builder: (context, _) {
        final r = rec;
        if (r == null) return const Scaffold(body: Center(child: Text('Enregistrement introuvable')));
        final enTraitement = etat.estEnTraitement(r);
        final theme = Theme.of(context);

        return Scaffold(
          appBar: AppBar(
            title: TextField(
              controller: _titre,
              decoration: const InputDecoration(border: InputBorder.none, isDense: true),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              onSubmitted: (v) async {
                r.titre = v.trim().isEmpty ? r.titre : v.trim();
                r.titrePerso = true;
                await etat.sauver(r);
                _message('Titre enregistré ✓');
              },
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Supprimer',
                onPressed: enTraitement ? null : _supprimer,
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${formaterDate(r.creeLe)} · ${formaterDuree(r.dureeSecondes)}',
                        style: TextStyle(fontSize: 12.5, color: theme.hintColor),
                      ),
                    ),
                    BadgeStatut(statut: r.statut),
                  ],
                ),
              ),
              _lecteurAudio(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: enTraitement ? null : _traiter,
                        child: Text(_libelleBouton(r)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: r.transcription == null ? null : _exporter,
                      child: const Text('Exporter'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: (r.synthese == null && r.traduction == null) ? null : _partager,
                      child: const Icon(Icons.ios_share, size: 18),
                    ),
                  ],
                ),
              ),
              if (enTraitement) _barreProgression(context),
              if (r.erreur != null && !enTraitement)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Couleurs.rouge.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(r.erreur!,
                        style: TextStyle(
                            fontSize: 13,
                            color: theme.brightness == Brightness.dark
                                ? Couleurs.rougeSombre
                                : Couleurs.rouge)),
                  ),
                ),
              TabBar(
                controller: _onglets,
                labelColor: theme.colorScheme.primary,
                indicatorColor: theme.colorScheme.primary,
                tabs: const [
                  Tab(text: 'Résumé'),
                  Tab(text: 'Traduction'),
                  Tab(text: 'النص العربي'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _onglets,
                  children: [
                    _ongletResume(context, r),
                    _ongletTexte(context, r.traduction,
                        'La traduction apparaîtra ici après le traitement.'),
                    _ongletTexte(context, r.transcription,
                        'La transcription arabe apparaîtra ici après le traitement.',
                        arabe: true),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _libelleBouton(Enregistrement r) {
    if (r.statut == Statut.erreur) return 'Réessayer';
    if (r.statut == Statut.termine) return 'Retraiter';
    if (r.transcription != null) return 'Continuer';
    return 'Transcrire & traduire';
  }

  Widget _lecteurAudio() {
    if (!_audioPret) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: StreamBuilder<Duration>(
        stream: _lecteur.positionStream,
        builder: (context, snap) {
          final position = snap.data ?? Duration.zero;
          final totale = _lecteur.duration ?? Duration.zero;
          final max = totale.inMilliseconds.toDouble();
          return Row(
            children: [
              StreamBuilder<PlayerState>(
                stream: _lecteur.playerStateStream,
                builder: (context, s) {
                  final enLecture = s.data?.playing ?? false;
                  return IconButton(
                    iconSize: 34,
                    icon: Icon(enLecture ? Icons.pause_circle : Icons.play_circle),
                    onPressed: () async {
                      if (enLecture) {
                        await _lecteur.pause();
                      } else {
                        if (_lecteur.processingState == ProcessingState.completed) {
                          await _lecteur.seek(Duration.zero);
                        }
                        await _lecteur.play();
                      }
                    },
                  );
                },
              ),
              Expanded(
                child: Slider(
                  value: position.inMilliseconds.clamp(0, max.toInt()).toDouble(),
                  max: max <= 0 ? 1 : max,
                  onChanged: (v) => _lecteur.seek(Duration(milliseconds: v.round())),
                ),
              ),
              Text(formaterDuree(position.inSeconds),
                  style: const TextStyle(fontSize: 12, fontFeatures: [FontFeature.tabularFigures()])),
              const SizedBox(width: 8),
            ],
          );
        },
      ),
    );
  }

  Widget _barreProgression(BuildContext context) {
    final a = etat.avancement;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(a?.libelle ?? 'Traitement…', style: const TextStyle(fontSize: 13))),
          ],
        ),
      ),
    );
  }

  Widget _ongletTexte(BuildContext context, String? texte, String vide, {bool arabe = false}) {
    if (texte == null || texte.trim().isEmpty) return _vide(context, vide);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: SelectableText(
        texte,
        textDirection: arabe ? TextDirection.rtl : TextDirection.ltr,
        textAlign: arabe ? TextAlign.right : TextAlign.left,
        style: arabe ? styleArabe(context) : const TextStyle(fontSize: 15.5, height: 1.6),
      ),
    );
  }

  Widget _vide(BuildContext context, String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).hintColor, height: 1.6)),
        ),
      );

  Widget _ongletResume(BuildContext context, Enregistrement r) {
    final s = r.synthese;
    if (s == null) {
      return _vide(context,
          'Le résumé, les points clés et les citations apparaîtront ici après le traitement.');
    }
    final theme = Theme.of(context);
    final sombre = theme.brightness == Brightness.dark;

    Widget titre(String t) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(t,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: accentTexte(context))),
        );

    Widget puces(List<String> items) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: items
              .map((t) => Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('•  '),
                        Expanded(child: SelectableText(t, style: const TextStyle(height: 1.5))),
                      ],
                    ),
                  ))
              .toList(),
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (s.theme.isNotEmpty)
            Container(
              padding: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: sombre ? Couleurs.orSombre : Couleurs.or, width: 3),
                ),
              ),
              child: Text(s.theme,
                  style: TextStyle(
                      fontStyle: FontStyle.italic, color: theme.hintColor, height: 1.5)),
            ),
          titre('Résumé'),
          SelectableText(s.resume, style: const TextStyle(fontSize: 15.5, height: 1.6)),
          if (s.pointsCles.isNotEmpty) ...[titre('Points clés'), puces(s.pointsCles)],
          if (s.citations.isNotEmpty) ...[
            titre('Versets & hadiths cités'),
            ...s.citations.map((c) => _carteCitation(context, c)),
          ],
          if (s.conseils.isNotEmpty) ...[titre('Conseils pratiques'), puces(s.conseils)],
          if (s.douas.isNotEmpty) ...[titre('Douas'), puces(s.douas)],
        ],
      ),
    );
  }

  Widget _carteCitation(BuildContext context, Citation c) {
    final theme = Theme.of(context);
    final sombre = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: sombre ? Couleurs.orSombre : Couleurs.or, width: 3),
          top: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
          right: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
          bottom: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            c.texteArabe,
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.right,
            style: styleArabe(context, taille: 19),
          ),
          const SizedBox(height: 8),
          SelectableText(c.traduction, style: const TextStyle(fontSize: 14.5, height: 1.5)),
          const SizedBox(height: 8),
          Text(
            '${c.type == 'coran' ? '📖' : c.type == 'hadith' ? '💬' : '•'} ${c.reference}',
            style: TextStyle(fontSize: 12, color: theme.hintColor),
          ),
        ],
      ),
    );
  }
}
