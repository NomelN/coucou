# Mochi's voice lines

Recorded lines played when Settings → General → Voice is set to **Mochi**. The WAV files are kept out of git (see `.gitignore`); without them, Coucou falls back to the Mac's voice.

- Format: WAV, 48 kHz, stereo, 16-bit, silence trimmed at both ends (same as `../sounds/`).
- Names: `name.wav`, or variants `name-1.wav`, `name-2.wav`… picked at random, never the same twice in a row.
- Agents: `fini` (finished), `erreur` (failed), `feu-vert` (permission), `question` (Claude asks a question), `limite` (usage limit).
- Services: `deploy-ok`, `deploy-erreur` (Vercel), `ci-ok`, `ci-erreur`, `review` (GitHub), `paiement` (Stripe), `mail` (new mail), `mail-envoye` (mail sent).
- Reactions: `coucou` (greeting), `claque` (slap), `sonne` (dizzy), `amour` (love), `fier` (search result), `fichier` (file swallowed), `baille` (not used yet).
- A missing service line falls back to the Mac's voice; a missing reaction stays silent.
