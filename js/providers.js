// Connecteurs vers les API d'IA. Tout part directement du navigateur :
// les clés restent sur le téléphone, l'audio n'est envoyé qu'au fournisseur choisi.
//
// - Gemini : transcription (audio accepté nativement) + traduction/synthèse.
//            Clé gratuite sur https://aistudio.google.com
// - OpenAI : transcription Whisper + traduction/synthèse (GPT).
// - Claude (Anthropic) : traduction/synthèse (pas de transcription audio).
// - demo   : contenu fictif, pour essayer l'app sans clé.

export const MODELES = {
  gemini: 'gemini-2.5-flash',
  openaiTranscription: 'whisper-1',
  openaiTexte: 'gpt-4o-mini',
  claudeParDefaut: 'claude-opus-4-8',
};

export const CHOIX_MODELES_CLAUDE = [
  { id: 'claude-opus-4-8', label: 'Claude Opus 4.8 — meilleure qualité (défaut)' },
  { id: 'claude-sonnet-5', label: 'Claude Sonnet 5 — rapide et équilibré' },
  { id: 'claude-haiku-4-5', label: 'Claude Haiku 4.5 — le plus économique' },
];

// ---------------------------------------------------------------- utilitaires

function erreurHttp(nom, statut, corps) {
  let detail = corps;
  try {
    const j = JSON.parse(corps);
    detail = j.error?.message || j.error?.type || corps;
  } catch { }
  const e = new Error(`${nom} : erreur ${statut} — ${String(detail).slice(0, 300)}`);
  e.statut = statut;
  return e;
}

function erreurReseau(nom) {
  return new Error(`${nom} : impossible de joindre le service. Vérifie ta connexion internet.`);
}

async function fetchJson(nom, url, options) {
  let rep;
  try { rep = await fetch(url, options); }
  catch { throw erreurReseau(nom); }
  if (!rep.ok) throw erreurHttp(nom, rep.status, await rep.text().catch(() => ''));
  return rep.json();
}

function blobVersBase64(blob) {
  return new Promise((resolve, reject) => {
    const lecteur = new FileReader();
    lecteur.onload = () => resolve(String(lecteur.result).split(',')[1]);
    lecteur.onerror = () => reject(lecteur.error);
    lecteur.readAsDataURL(blob);
  });
}

// Type MIME « propre » pour les API (sans ;codecs=…)
export function mimeSimple(mimeType) {
  const m = (mimeType || 'audio/webm').split(';')[0].trim().toLowerCase();
  return m || 'audio/webm';
}

// Lit un flux SSE et appelle cb(objetJson) pour chaque ligne `data: {...}`
async function lireSSE(nom, reponse, cb) {
  const lecteur = reponse.body.getReader();
  const decodeur = new TextDecoder();
  let tampon = '';
  for (;;) {
    const { done, value } = await lecteur.read();
    if (done) break;
    tampon += decodeur.decode(value, { stream: true });
    const lignes = tampon.split('\n');
    tampon = lignes.pop();
    for (const ligne of lignes) {
      const l = ligne.trim();
      if (!l.startsWith('data:')) continue;
      const charge = l.slice(5).trim();
      if (!charge || charge === '[DONE]') continue;
      let obj;
      try { obj = JSON.parse(charge); } catch { continue; }
      cb(obj);
    }
  }
}

// Le modèle renvoie parfois le JSON entouré de ```json … ``` : on nettoie.
export function parseJsonSouple(texte) {
  if (!texte) throw new Error('Réponse vide du modèle.');
  let t = texte.trim();
  const fence = t.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fence) t = fence[1].trim();
  try { return JSON.parse(t); } catch { }
  const debut = t.indexOf('{');
  const fin = t.lastIndexOf('}');
  if (debut >= 0 && fin > debut) {
    return JSON.parse(t.slice(debut, fin + 1));
  }
  throw new Error('Le modèle n’a pas renvoyé un JSON valide.');
}

// ---------------------------------------------------------------------- Gemini

const GEMINI_BASE = 'https://generativelanguage.googleapis.com';
const LIMITE_INLINE = 15 * 1024 * 1024; // au-delà : upload via l'API Files

async function geminiGenerer(cle, contents, generationConfig, systemInstruction) {
  const corps = { contents, generationConfig };
  if (systemInstruction) corps.systemInstruction = { parts: [{ text: systemInstruction }] };
  const url = `${GEMINI_BASE}/v1beta/models/${MODELES.gemini}:generateContent?key=${encodeURIComponent(cle)}`;

  let rep;
  try {
    rep = await fetch(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(corps),
    });
  } catch { throw erreurReseau('Gemini'); }

  // Certains réglages (thinkingConfig…) ne sont pas acceptés par tous les
  // modèles : on retente une fois sans, plutôt que d'échouer.
  if (rep.status === 400 && generationConfig?.thinkingConfig) {
    const { thinkingConfig, ...reste } = generationConfig;
    return geminiGenerer(cle, contents, reste, systemInstruction);
  }
  if (!rep.ok) throw erreurHttp('Gemini', rep.status, await rep.text().catch(() => ''));

  const data = await rep.json();
  const cand = data.candidates?.[0];
  const texte = (cand?.content?.parts || []).map(p => p.text || '').join('');
  if (!texte) {
    const raison = data.promptFeedback?.blockReason || cand?.finishReason || 'réponse vide';
    throw new Error(`Gemini n’a pas renvoyé de texte (${raison}).`);
  }
  return texte;
}

async function geminiUploadFichier(cle, blob, mimeType) {
  // Upload « resumable » de l'API Files, en deux requêtes.
  let rep;
  try {
    rep = await fetch(`${GEMINI_BASE}/upload/v1beta/files?key=${encodeURIComponent(cle)}`, {
      method: 'POST',
      headers: {
        'x-goog-upload-protocol': 'resumable',
        'x-goog-upload-command': 'start',
        'x-goog-upload-header-content-length': String(blob.size),
        'x-goog-upload-header-content-type': mimeType,
        'content-type': 'application/json',
      },
      body: JSON.stringify({ file: { display_name: 'khoutba-audio' } }),
    });
  } catch { throw erreurReseau('Gemini (upload)'); }
  if (!rep.ok) throw erreurHttp('Gemini (upload)', rep.status, await rep.text().catch(() => ''));

  const urlUpload = rep.headers.get('x-goog-upload-url');
  if (!urlUpload) throw new Error('Gemini (upload) : URL de téléversement absente.');

  const rep2 = await fetch(urlUpload, {
    method: 'POST',
    headers: {
      'x-goog-upload-offset': '0',
      'x-goog-upload-command': 'upload, finalize',
    },
    body: blob,
  });
  if (!rep2.ok) throw erreurHttp('Gemini (upload)', rep2.status, await rep2.text().catch(() => ''));
  let fichier = (await rep2.json()).file;

  // Attendre que le fichier soit traité (état ACTIVE), au plus ~2 min.
  const debut = Date.now();
  while (fichier.state === 'PROCESSING') {
    if (Date.now() - debut > 120000) throw new Error('Gemini : le traitement du fichier audio prend trop de temps.');
    await new Promise(r => setTimeout(r, 3000));
    fichier = await fetchJson('Gemini', `${GEMINI_BASE}/v1beta/${fichier.name}?key=${encodeURIComponent(cle)}`);
  }
  if (fichier.state !== 'ACTIVE') throw new Error(`Gemini : fichier audio refusé (état ${fichier.state}).`);
  return fichier;
}

export async function transcrireGemini(cle, blob, mimeType, prompt) {
  const mime = mimeSimple(mimeType);
  let partAudio;
  if (blob.size <= LIMITE_INLINE) {
    partAudio = { inlineData: { mimeType: mime, data: await blobVersBase64(blob) } };
  } else {
    const fichier = await geminiUploadFichier(cle, blob, mime);
    partAudio = { fileData: { mimeType: mime, fileUri: fichier.uri } };
  }
  const contents = [{ role: 'user', parts: [partAudio, { text: prompt }] }];
  return geminiGenerer(cle, contents, {
    temperature: 0.2,
    maxOutputTokens: 65536,
    // La transcription n'a pas besoin de « réflexion » : plus rapide, moins cher.
    thinkingConfig: { thinkingBudget: 0 },
  });
}

export async function genererGemini(cle, { system, user, json }) {
  const generationConfig = { temperature: 0.3, maxOutputTokens: 65536 };
  if (json) generationConfig.responseMimeType = 'application/json';
  return geminiGenerer(cle, [{ role: 'user', parts: [{ text: user }] }], generationConfig, system);
}

// ---------------------------------------------------------------------- OpenAI

const OPENAI_BASE = 'https://api.openai.com';
const LIMITE_WHISPER = 25 * 1024 * 1024;

function nomFichierAudio(mimeType) {
  const m = mimeSimple(mimeType);
  if (m.includes('mp4')) return 'audio.m4a';
  if (m.includes('mpeg') || m.includes('mp3')) return 'audio.mp3';
  if (m.includes('wav')) return 'audio.wav';
  if (m.includes('ogg')) return 'audio.ogg';
  if (m.includes('flac')) return 'audio.flac';
  return 'audio.webm';
}

export async function transcrireOpenAI(cle, blob, mimeType) {
  if (blob.size > LIMITE_WHISPER) {
    throw new Error(
      `Fichier trop gros pour Whisper (${(blob.size / 1048576).toFixed(1)} Mo, limite 25 Mo). ` +
      'Utilise Gemini pour la transcription des très longs enregistrements.'
    );
  }
  const form = new FormData();
  form.append('file', blob, nomFichierAudio(mimeType));
  form.append('model', MODELES.openaiTranscription);
  form.append('language', 'ar');
  form.append('response_format', 'text');
  form.append('temperature', '0');

  let rep;
  try {
    rep = await fetch(`${OPENAI_BASE}/v1/audio/transcriptions`, {
      method: 'POST',
      headers: { authorization: `Bearer ${cle}` },
      body: form,
    });
  } catch { throw erreurReseau('OpenAI (Whisper)'); }
  if (!rep.ok) throw erreurHttp('OpenAI (Whisper)', rep.status, await rep.text().catch(() => ''));
  return (await rep.text()).trim();
}

export async function genererOpenAI(cle, { system, user, schema, onDelta }) {
  const corps = {
    model: MODELES.openaiTexte,
    messages: [
      { role: 'system', content: system },
      { role: 'user', content: user },
    ],
    stream: true,
    max_completion_tokens: 16000,
  };
  if (schema) {
    corps.response_format = {
      type: 'json_schema',
      json_schema: { name: 'synthese_khoutba', strict: true, schema },
    };
  }

  let rep;
  try {
    rep = await fetch(`${OPENAI_BASE}/v1/chat/completions`, {
      method: 'POST',
      headers: { authorization: `Bearer ${cle}`, 'content-type': 'application/json' },
      body: JSON.stringify(corps),
    });
  } catch { throw erreurReseau('OpenAI'); }
  if (!rep.ok) throw erreurHttp('OpenAI', rep.status, await rep.text().catch(() => ''));

  let texte = '';
  await lireSSE('OpenAI', rep, (obj) => {
    const morceau = obj.choices?.[0]?.delta?.content;
    if (morceau) { texte += morceau; if (onDelta) onDelta(texte); }
  });
  return texte;
}

// ------------------------------------------------------------------ Anthropic

const ANTHROPIC_BASE = 'https://api.anthropic.com';

export async function genererClaude(cle, { modele, system, user, schema, onDelta, reflexion }) {
  const corps = {
    model: modele || MODELES.claudeParDefaut,
    max_tokens: schema ? 16000 : 32000,
    system,
    messages: [{ role: 'user', content: user }],
    stream: true,
  };
  // Réflexion adaptative pour l'analyse (repérer versets et hadiths demande
  // un peu de raisonnement) ; inutile pour la traduction pure.
  if (reflexion) corps.thinking = { type: 'adaptive' };
  if (schema) corps.output_config = { format: { type: 'json_schema', schema } };

  let rep;
  try {
    rep = await fetch(`${ANTHROPIC_BASE}/v1/messages`, {
      method: 'POST',
      headers: {
        'x-api-key': cle,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
        // Autorise l'appel direct depuis le navigateur (app sans serveur).
        'anthropic-dangerous-direct-browser-access': 'true',
      },
      body: JSON.stringify(corps),
    });
  } catch { throw erreurReseau('Claude'); }
  if (!rep.ok) throw erreurHttp('Claude', rep.status, await rep.text().catch(() => ''));

  let texte = '';
  let stopReason = null;
  await lireSSE('Claude', rep, (ev) => {
    if (ev.type === 'content_block_delta' && ev.delta?.type === 'text_delta') {
      texte += ev.delta.text;
      if (onDelta) onDelta(texte);
    } else if (ev.type === 'message_delta') {
      stopReason = ev.delta?.stop_reason || stopReason;
    } else if (ev.type === 'error') {
      throw new Error(`Claude : ${ev.error?.message || 'erreur de flux'}`);
    }
  });
  if (stopReason === 'refusal') throw new Error('Claude a refusé de traiter ce contenu.');
  if (stopReason === 'max_tokens') texte += '\n\n[… réponse tronquée : texte trop long]';
  return texte;
}

// ---------------------------------------------------------------------- Démo

const DEMO_TRANSCRIPTION = `الحمد لله ربّ العالمين، والصلاة والسلام على أشرف المرسلين، سيدنا محمد وعلى آله وصحبه أجمعين. أما بعد، فيا عباد الله، أوصيكم ونفسي بتقوى الله عز وجل.

عباد الله، إنّ نعم الله علينا لا تُعدّ ولا تُحصى: نعمة الإيمان، ونعمة الصحة، ونعمة الأمن، ونعمة الأهل والولد. قال الله تعالى: «وَإِذْ تَأَذَّنَ رَبُّكُمْ لَئِن شَكَرْتُمْ لَأَزِيدَنَّكُمْ وَلَئِن كَفَرْتُمْ إِنَّ عَذَابِي لَشَدِيدٌ».

فالشكر يكون بالقلب واللسان والجوارح: بالقلب اعترافًا بفضل الله، وباللسان حمدًا وثناءً، وبالجوارح طاعةً واستعمالًا للنعم في مرضاة الله. وقال رسول الله صلى الله عليه وسلم: «لا يشكر اللهَ من لا يشكر الناس».

فاتقوا الله عباد الله، واشكروه على نعمه يزدكم من فضله، وحافظوا على الصلاة في وقتها، وأحسنوا إلى والديكم وجيرانكم. أقول قولي هذا وأستغفر الله لي ولكم.`;

const DEMO_TRADUCTION = `Louange à Allah, Seigneur des mondes. Que la paix et le salut soient sur le plus noble des messagers, notre maître Mohammed ﷺ, ainsi que sur sa famille et l'ensemble de ses compagnons. Ceci étant dit : ô serviteurs d'Allah, je vous recommande, à vous comme à moi-même, la crainte d'Allah, à Lui la puissance et la majesté.

Serviteurs d'Allah, les bienfaits d'Allah sur nous ne se comptent pas : le bienfait de la foi, celui de la santé, celui de la sécurité, celui de la famille et des enfants. Allah le Très-Haut a dit : « Et lorsque votre Seigneur proclama : si vous êtes reconnaissants, très certainement J'augmenterai [Mes bienfaits] pour vous ; mais si vous êtes ingrats, Mon châtiment sera terrible » (Ibrahim, 14:7).

La gratitude s'exprime par le cœur, par la langue et par les membres : par le cœur, en reconnaissant la grâce d'Allah ; par la langue, en Le louant et en faisant Son éloge ; par les membres, en Lui obéissant et en employant Ses bienfaits dans ce qui Le satisfait. Le Messager d'Allah ﷺ a dit : « Ne remercie pas Allah celui qui ne remercie pas les gens » (rapporté par Abou Dawoud et at-Tirmidhi).

Craignez donc Allah, serviteurs d'Allah, et remerciez-Le pour Ses bienfaits, Il vous en accordera davantage par Sa grâce. Préservez la prière à son heure, et soyez bons envers vos parents et vos voisins. Je dis ces paroles et je demande pardon à Allah pour moi et pour vous.`;

const DEMO_SYNTHESE = {
  titre: 'La gratitude envers Allah (ach-choukr)',
  theme: "Reconnaître les bienfaits d'Allah et les faire fructifier par la reconnaissance du cœur, de la langue et des actes.",
  resume: "L'imam rappelle que les bienfaits d'Allah — la foi, la santé, la sécurité, la famille — sont innombrables, et que la gratitude est la clé de leur préservation et de leur augmentation, comme le promet le verset de la sourate Ibrahim.\n\nIl détaille ensuite les trois niveaux de la gratitude : celle du cœur (reconnaître que tout vient d'Allah), celle de la langue (la louange), et celle des membres (utiliser les bienfaits dans l'obéissance). Il conclut en liant la gratitude envers Allah à la gratitude envers les gens, et exhorte à préserver la prière et la bonté envers les parents et les voisins.",
  points_cles: [
    "Les bienfaits d'Allah sont innombrables : foi, santé, sécurité, famille.",
    'La gratitude fait augmenter les bienfaits ; l’ingratitude expose au châtiment.',
    'Trois niveaux de gratitude : le cœur, la langue, les membres.',
    'Remercier les gens fait partie de la gratitude envers Allah.',
    'Recommandations finales : la prière à l’heure, la bonté envers parents et voisins.',
  ],
  citations: [
    {
      type: 'coran',
      texte_arabe: 'وَإِذْ تَأَذَّنَ رَبُّكُمْ لَئِن شَكَرْتُمْ لَأَزِيدَنَّكُمْ وَلَئِن كَفَرْتُمْ إِنَّ عَذَابِي لَشَدِيدٌ',
      traduction: "Et lorsque votre Seigneur proclama : si vous êtes reconnaissants, très certainement J'augmenterai [Mes bienfaits] pour vous ; mais si vous êtes ingrats, Mon châtiment sera terrible.",
      reference: 'Sourate Ibrahim, 14:7',
    },
    {
      type: 'hadith',
      texte_arabe: 'لا يشكر اللهَ من لا يشكر الناس',
      traduction: 'Ne remercie pas Allah celui qui ne remercie pas les gens.',
      reference: 'Abou Dawoud et at-Tirmidhi',
    },
  ],
  conseils: [
    'Prendre un moment chaque jour pour énumérer les bienfaits reçus et dire al-hamdou lillah.',
    'Employer sa santé et son temps dans ce qui plaît à Allah.',
    'Remercier concrètement les personnes qui nous font du bien.',
    'Veiller à la prière à son heure.',
    'Rendre visite et faire du bien à ses parents et voisins.',
  ],
  douas: [
    "Ô Allah, aide-nous à T'évoquer, à Te remercier et à T'adorer de la meilleure façon.",
  ],
};

function attendre(ms) { return new Promise(r => setTimeout(r, ms)); }

export async function transcrireDemo() {
  await attendre(1800);
  return DEMO_TRANSCRIPTION;
}

export async function genererDemo({ schema, onDelta }) {
  if (schema) { await attendre(1200); return JSON.stringify(DEMO_SYNTHESE); }
  // Simule un flux de traduction
  const morceaux = DEMO_TRADUCTION.split(/(?<=\. )/);
  let texte = '';
  for (const m of morceaux) {
    texte += m;
    if (onDelta) onDelta(texte);
    await attendre(60);
  }
  return DEMO_TRADUCTION;
}
