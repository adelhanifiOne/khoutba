// Chaîne de traitement d'une khoutba :
//   audio → 1. transcription (arabe) → 2. traduction → 3. synthèse structurée
//
// Chaque étape est sauvegardée dès qu'elle réussit : si la synthèse échoue,
// la transcription et la traduction restent acquises.

import { sauverEnregistrement } from './db.js';
import {
  transcrireGemini, genererGemini,
  transcrireOpenAI, genererOpenAI,
  genererClaude,
  transcrireDemo, genererDemo,
  parseJsonSouple,
} from './providers.js';

export const LANGUES = { fr: 'français', en: 'anglais' };

// Longueur max du texte envoyé à l'analyse (~1 h 30 de prêche, large).
const MAX_CARACTERES = 300000;

// ------------------------------------------------------------------- prompts

const PROMPT_TRANSCRIPTION = `Transcris intégralement et fidèlement cet enregistrement audio. Il s'agit d'un prêche (khoutba) prononcé dans une mosquée, principalement en arabe littéraire, parfois mêlé de dialecte algérien.

Consignes :
- Écris la transcription en arabe, avec la ponctuation, découpée en paragraphes.
- Ne traduis pas, ne résume pas, n'ajoute aucun commentaire.
- Ignore l'adhan, les bruits de fond et les répétitions techniques (micro).
- Si un passage est incompréhensible, écris [غير مسموع].
- Commence directement par le texte, sans introduction.`;

function promptSystemTraduction(langue) {
  return `Tu es un traducteur professionnel arabe → ${langue}, spécialisé dans le discours religieux musulman (khoutbas du vendredi).

Règles :
- Traduis fidèlement et intégralement, sans résumer ni omettre de passages.
- Conserve le découpage en paragraphes du texte d'origine.
- Pour les versets du Coran : donne une traduction soignée entre guillemets « … », suivie de la référence (sourate, numéro:verset) si tu l'identifies avec certitude.
- Pour les hadiths : traduis, et indique la source entre parenthèses si elle est citée ou connue.
- Rends les formules pieuses de façon naturelle (ex. : ﷺ → « que la paix et le salut soient sur lui »).
- Si le texte contient [غير مسموع], écris [inaudible].
- Réponds uniquement avec la traduction, sans préambule ni commentaire.`;
}

function promptSystemSynthese(langue) {
  return `Tu es un assistant qui aide un fidèle francophone à comprendre la khoutba du vendredi qu'il a enregistrée à la mosquée. À partir de la transcription arabe fournie, produis une synthèse claire et fidèle en ${langue}, au format JSON demandé.

Consignes :
- "titre" : un titre court et parlant pour cette khoutba.
- "theme" : le sujet principal en une ou deux phrases.
- "resume" : un résumé fidèle en deux à quatre paragraphes (séparés par des sauts de ligne), qui suit le fil du prêche.
- "points_cles" : 4 à 8 idées essentielles, formulées simplement.
- "citations" : les versets du Coran et hadiths cités : texte arabe exact tel qu'entendu, traduction, et référence ("type" vaut "coran", "hadith" ou "autre" ; si la référence est incertaine, écris "référence à vérifier").
- "conseils" : les recommandations pratiques données par l'imam, applicables au quotidien.
- "douas" : les invocations notables de la fin du prêche, traduites (liste vide si aucune).
- N'invente rien : tout doit venir de la transcription. En cas de doute, signale-le.`;
}

export const SCHEMA_SYNTHESE = {
  type: 'object',
  properties: {
    titre: { type: 'string' },
    theme: { type: 'string' },
    resume: { type: 'string' },
    points_cles: { type: 'array', items: { type: 'string' } },
    citations: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          type: { type: 'string', enum: ['coran', 'hadith', 'autre'] },
          texte_arabe: { type: 'string' },
          traduction: { type: 'string' },
          reference: { type: 'string' },
        },
        required: ['type', 'texte_arabe', 'traduction', 'reference'],
        additionalProperties: false,
      },
    },
    conseils: { type: 'array', items: { type: 'string' } },
    douas: { type: 'array', items: { type: 'string' } },
  },
  required: ['titre', 'theme', 'resume', 'points_cles', 'citations', 'conseils', 'douas'],
  additionalProperties: false,
};

// -------------------------------------------------------------- orchestration

function verifierCle(reglages, fournisseur) {
  const cle = (reglages.cles || {})[fournisseur];
  if (!cle) {
    const noms = { gemini: 'Gemini', openai: 'OpenAI', anthropic: 'Claude (Anthropic)' };
    throw new Error(`Clé API ${noms[fournisseur]} manquante — ajoute-la dans les réglages.`);
  }
  return cle;
}

async function etapeTranscription(rec, reglages, onStatus) {
  onStatus({ phase: 'transcription' });
  const stt = reglages.demo ? 'demo' : reglages.stt;
  if (stt === 'demo') return transcrireDemo();
  if (stt === 'gemini') {
    return transcrireGemini(verifierCle(reglages, 'gemini'), rec.audio, rec.mimeType, PROMPT_TRANSCRIPTION);
  }
  if (stt === 'openai') {
    return transcrireOpenAI(verifierCle(reglages, 'openai'), rec.audio, rec.mimeType);
  }
  throw new Error('Choisis un fournisseur de transcription dans les réglages (Gemini ou OpenAI).');
}

async function etapeGeneration(reglages, params) {
  const llm = reglages.demo ? 'demo' : reglages.llm;
  if (llm === 'demo') return genererDemo(params);
  if (llm === 'gemini') {
    const texte = await genererGemini(verifierCle(reglages, 'gemini'), { system: params.system, user: params.user, json: !!params.schema });
    if (params.onDelta) params.onDelta(texte);
    return texte;
  }
  if (llm === 'openai') return genererOpenAI(verifierCle(reglages, 'openai'), params);
  if (llm === 'anthropic') {
    return genererClaude(verifierCle(reglages, 'anthropic'), {
      modele: reglages.modeleClaude,
      system: params.system,
      user: params.user,
      schema: params.schema,
      onDelta: params.onDelta,
      reflexion: !!params.schema,
    });
  }
  throw new Error('Choisis un fournisseur de traduction/synthèse dans les réglages.');
}

let _enCours = false;
export function traitementEnCours() { return _enCours; }

// Traite un enregistrement. `onStatus({phase, partiel})` informe l'interface.
// `options.forcer` relance tout même si des résultats existent déjà.
export async function traiterEnregistrement(rec, reglages, onStatus = () => {}, options = {}) {
  if (_enCours) throw new Error('Un traitement est déjà en cours — attends qu’il se termine.');
  _enCours = true;
  const langue = LANGUES[reglages.langue] || LANGUES.fr;

  try {
    // 1. Transcription
    if (!rec.transcript || options.forcer) {
      rec.statut = 'transcription';
      rec.erreur = null;
      await sauverEnregistrement(rec);
      rec.transcript = (await etapeTranscription(rec, reglages, onStatus)).trim();
      rec.statut = 'transcrit';
      await sauverEnregistrement(rec);
    }

    const source = rec.transcript.slice(0, MAX_CARACTERES);

    // 2. Traduction
    if (!rec.traduction || options.forcer) {
      rec.statut = 'traduction';
      await sauverEnregistrement(rec);
      onStatus({ phase: 'traduction' });
      rec.traduction = (await etapeGeneration(reglages, {
        system: promptSystemTraduction(langue),
        user: `Voici la transcription de la khoutba à traduire :\n\n${source}`,
        onDelta: (t) => onStatus({ phase: 'traduction', partiel: t }),
      })).trim();
      rec.statut = 'traduit';
      await sauverEnregistrement(rec);
    }

    // 3. Synthèse structurée
    rec.statut = 'synthese';
    await sauverEnregistrement(rec);
    onStatus({ phase: 'synthese' });
    const brut = await etapeGeneration(reglages, {
      system: promptSystemSynthese(langue),
      user: `Voici la transcription arabe de la khoutba :\n\n${source}\n\nRéponds uniquement avec le JSON demandé.`,
      schema: SCHEMA_SYNTHESE,
    });
    rec.synthese = parseJsonSouple(brut);
    if (!rec.synthese.titre || !rec.synthese.resume) {
      throw new Error('Synthèse incomplète renvoyée par le modèle — réessaie.');
    }

    rec.statut = 'termine';
    rec.erreur = null;
    // Titre automatique s'il n'a pas été personnalisé
    if (!rec.titrePerso && rec.synthese.titre) rec.titre = rec.synthese.titre;
    await sauverEnregistrement(rec);
    onStatus({ phase: 'termine' });
    return rec;
  } catch (e) {
    rec.statut = 'erreur';
    rec.erreur = e.message || String(e);
    await sauverEnregistrement(rec).catch(() => {});
    throw e;
  } finally {
    _enCours = false;
  }
}

// Après un crash / fermeture pendant un traitement, ramène le statut à un état stable.
export function statutStable(rec) {
  if (['transcription'].includes(rec.statut)) return rec.transcript ? 'transcrit' : 'pret';
  if (['traduction'].includes(rec.statut)) return rec.traduction ? 'traduit' : 'transcrit';
  if (['synthese'].includes(rec.statut)) return 'traduit';
  return rec.statut;
}
