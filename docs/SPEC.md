# Notch Buddy — spécification

Toutes les mesures sont en points macOS. Les valeurs viennent de `reference/notch-buddy.html` (constantes `NW`, `NH`, `EW`, `VIEWS`, `STATES`, `EMOTES`, `PISTES`, `AGENTS`, classe `Bot`). En cas de doute, relire le code du prototype.

---

## 1. Fenêtre et notch

- Une `NSPanel` sans bordure : `styleMask [.borderless, .nonactivatingPanel]`, fond transparent, sans ombre, niveau au-dessus de la barre de menus (`.mainMenu + 3` ou équivalent qui passe au-dessus de la barre et des apps plein écran), `collectionBehavior [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`.
- Taille fixe 720 × 320, ancrée en haut au centre de l'écran qui a un notch. L'island est dessinée dedans, collée au bord haut.
- **Clics traversants** : la zone transparente ne doit jamais bloquer les clics. Toggle `ignoresMouseEvents` à 60 Hz selon que `NSEvent.mouseLocation` est dans la forme de l'island (plus 6 pt de marge) ou pas.
- La panel peut devenir key uniquement quand un champ texte de l'island a le focus (prompt, mail). Sinon elle ne vole jamais le focus.
- Détection du notch : `NSScreen.safeAreaInsets.top` > 0 et `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`. Largeur du notch `wN` = largeur écran − les deux zones auxiliaires ; hauteur `hN` = `safeAreaInsets.top`. Le prototype utilise `wN = 184`, `hN = 32` : dans l'app, prendre les vraies valeurs.
- Pas d'écran avec notch (Mac de bureau, écran externe ou capot fermé) : afficher sur l'écran principal une barre noire de 80 pt au repos (`hidden`), avec Mochi visible au centre et son animation en pause ; 240 pt en `compact`, en haut au centre. Hauteur plafonnée à 24 pt et à celle de la barre de menus ; personnage et pastilles adaptés à cette hauteur. Le salut se replie vers les dimensions réelles de la barre compacte. La zone de survol au repos ne déborde pas sous la barre. Les vues ouvertes gardent leur largeur de 640 pt.
- Suivi de la souris : polling de `NSEvent.mouseLocation` à chaque frame. Aucune permission nécessaire.

### Forme de l'island
- Rectangle noir `#000`, coins hauts carrés (il se fond dans le bord de l'écran), coins bas arrondis : 14 pt en hidden/peek/compact, 30 pt en expanded.
- Deux « oreilles » concaves de 14 pt aux coins hauts, à l'extérieur, pour que la forme coule dans le bord de l'écran (voir `#island::before/::after` du prototype).

## 2. Modes de l'island

| Mode | Largeur | Hauteur | Bonhomme | Agents secondaires |
|---|---|---|---|---|
| `hidden` | wN | hN | invisible | invisibles |
| `peek` | wN + 64 | hN | Ø 18, centre x = 19 | invisibles |
| `compact` | wN + 104 | hN | Ø 20, centre x = 27 | grille 2×2 dans l'oreille droite |
| `expanded` | 640 | selon la vue (§5) | selon la vue | selon la vue |

(Ø = diamètre du corps. Le canvas du personnage fait Ø / 0,6 de côté : le corps occupe 60 % du canvas, le reste sert aux particules, mains et badge.)

Grille compact : pastilles Ø 9,5 autour du point (largeur − 27, hN/2), écart ±6. 1 agent : centré. 2 : côte à côte. 3 : deux en haut, un en bas. 4 : carré.

## 3. Règles de comportement (validées par Louis)

1. **Rien ne tourne** → `hidden`. Totalement invisible.
2. **Souris sur le notch** alors que `hidden` → `peek` immédiatement, le bonhomme sort en faisant coucou (mains + son `peek` + son `greet`). Si la souris reste 650 ms → `expanded` (vue `overview`, ou `empty` s'il n'y a aucune tâche). Si elle part pendant le peek → retour `hidden` après 600 ms.
3. **Des tâches tournent et Louis est actif** → `compact` : très fin, le bonhomme visible, il suit la souris des yeux partout sur l'écran.
4. **Survol en compact** → `expanded` après 200 ms. Clic sur le bonhomme en compact → `expanded` tout de suite.
5. **Fermeture auto** : une fois ouverte, l'island se replie après **60 s sans activité** (mouvement de souris sur l'island, clic, frappe). Quitter l'island ne la ferme pas. Pendant les 10 dernières secondes, un trait de 2 pt en bas au centre (160 pt → 0, blanc 35 %) montre le compte à rebours. `Échap` ferme.
6. **Louis absent** (aucun mouvement de souris depuis 3 min, réglable) → `hidden`, même avec des tâches. Au premier mouvement → retour `compact` si des tâches tournent.
7. **Alertes** (permission, question, erreur) : l'island s'ouvre seule sur la vue de l'alerte, **même si Louis est absent**, et reste ouverte (pas de fermeture auto) jusqu'à sa réponse.
8. **Terminé** : l'island s'ouvre sur la vue `finished` pendant 8 s (le temps que Coucou l'annonce), puis retire la tâche et se replie. Souris sur l'island à ce moment-là → repli 1,5 s après sa sortie.
9. Plusieurs alertes en même temps : file d'attente, une à la fois, l'ordre d'arrivée.
10. **Focus** : le gros bonhomme représente la tâche en focus (la dernière alerte, sinon la première qui travaille). Les autres tâches sont les mini-bonhommes. Cliquer un mini-bonhomme le met en focus.

## 4. Animations de l'island

- Ouverture / agrandissement : 520 ms, ressort avec léger dépassement, équivalent `cubic-bezier(.32,1.22,.42,1)`. En SwiftUI, partir de `.spring(response: 0.5, dampingFraction: 0.72)` et ajuster à l'œil contre le prototype.
- Fermeture / rétrécissement : 340 ms, `cubic-bezier(.45,0,.2,1)`, sans dépassement.
- Largeur, hauteur, rayon, position et taille du bonhomme, position et taille des mini-bonhommes animent **ensemble** (effet « élément partagé » : les mini-bonhommes passent de la grille aux pastilles puis à la colonne sans disparaître).
- Contenu des vues : sortie 160 ms (opacité 0, flou 8, échelle 0,97) ; entrée 300 ms avec 160 ms de retard (après que le conteneur a commencé à grandir). L'en-tête apparaît avec 300 ms de retard.
- Mini-bonhommes : décalage de 35 ms par index.
- Libellés des pastilles : apparaissent 220 ms après le début du mouvement.
- Au passage en `expanded`, le bonhomme cligne des yeux.
- Sons : `open` à l'ouverture, `close` à la fermeture.

## 5. Vues (mode expanded, largeur 640)

Structure commune : en-tête de 34 pt (onglets à gauche : Vue d'ensemble, Demander, Déposer ; à droite : « N en cours » + bouton son + chevron ⌃ qui replie l'île comme `Échap`, grisé quand une carte est épinglée). Contenu inséré de 36 en haut, 10 à gauche, droite, bas. Cartes : rayon 20, fond `#141518`, bord blanc 3,5 %. Dans les vues autres que `overview`, les mini-bonhommes passent en **colonne** à droite (Ø 16, x = largeur − 31, y = 50 + i × 24) et la carte laisse 42 pt à droite.

Voile de couleur des cartes : dégradé radial depuis le bas (120 % × 90 %, centre 50 % / 130 %), couleur de l'état :
rouge `rgba(244,80,94,.55)`, vert `rgba(52,211,153,.5)`, rose `rgba(244,114,182,.55)`, ambre `rgba(245,165,36,.42)`, cyan `rgba(34,211,238,.38)`, indigo `rgba(99,102,241,.5)`, neutre `rgba(255,255,255,.08)`.

| Vue | Hauteur | Bonhomme (x, Ø) | Contenu | Capture |
|---|---|---|---|---|
| `overview` | 196 | 64, 70 | carte gauche 322 de large : ligne agent + défilé de tâches ; carte droite : pastilles | 03 |
| `empty` | 150 | 70, 62 | « Rien ne tourne pour l'instant. » + bouton « Demander à Claude » | 16 |
| `approval` | 206 | 62, 56 | agent + « Claude Code veut lancer une commande », bloc code, Refuser (N), Toujours autoriser, Autoriser (Y) | 04 |
| `question` | 196 | 62, 56 | agent + question (1/N) + options en boutons (single-select ou multi-select) + « Reply in terminal » ; bouton Send/Next pour multi-select ou multi-questions ; « Other… » → saisie libre | 05 |
| `error` | 190 | 62, 58 | agent + outil, titre, détail en rouge `#FF8D97`, Relancer, Ouvrir dans n8n | 06 |
| `finished` | 170 | 62, 58 | agent + résumé sur une ligne, sans bouton : se replie seule (§3 règle 8) | 07 |
| `confused` | 160 | 76, 66 | « Trop de claques d'un coup. » | 08 |
| `upload` | 176 | 140, 62 | zone pointillée, « Dépose tes fichiers ici », étiquettes | 09 |
| `uploading` | 150 | sur la barre, Ø 28 | « Envoi de fichier » + %, barre verte, le bonhomme est le curseur de la barre | 10 |
| `choose` | 170 | 60, 52 | « fichier est prêt. », Poser une question dessus, Envoyer par mail | 11 |
| `mail` | 210 | 56, 46 | champs À, Objet (+ Message optionnel), Envoyer, Annuler | 12 |
| `prompt` | 156 | 52, 44 | pastille de contexte + puce de modèle (clic → sélecteur fournisseur/modèle) + champ + micro + envoyer | 13 |
| `searching` | 156 | 52, 44 | contexte + texte scintillant « Claude lit la page et cherche sur le web… » | 14 |
| `result` | 262 (s'adapte au contenu, max 320) | 52, 44 | titre, 3 lignes de résultat, boutons | 15 |
| `note` | 136 | 60, 50 | message court (mail envoyé, copié, j'ouvre n8n…), se ferme seul après 2 s | — |

Centre vertical du bonhomme : 36 + (hauteur − 46) / 2, sauf `result` (y = 86).

### Défilé de tâches (overview)
- Position x = 112 dans la carte, fenêtre de 96 pt avec masque dégradé haut/bas, 4 lignes de 30 pt (précédente, courante, suivante, suivante+1).
- Ligne courante : 14 pt medium, texte scintillant (dégradé gris → blanc → gris qui balaie en 2,2 s). Autres : 13 pt `#5F646D`, icône 14 pt.
- Toutes les 2,8 s, si la tâche en focus travaille : tout monte de 30 pt en 450 ms `cubic-bezier(.3,.9,.3,1)`.
- Dans l'app réelle, les lignes = les dernières actions de la session (outil + cible : « Edit Invoice.swift », « Bash npm test ») ou les nœuds n8n.

### Diff en direct

Quand une étape du fil est une modification de fichier (préfixe interne `\u{E001}`), elle s'affiche avec le nom du fichier et le bilan `+N −M` en couleur. Un clic sur la ligne courante ou la ligne précédente ouvre la carte diff (voir DiffCardView) dans la carte gauche de la vue principale, en remplacement du fil — que la pastille soit intégrée (integration_claude, agent_cursor…) ou non. Échap ou le bouton ← de l'en-tête ferme la carte. En fin de tâche (Stop), la ligne courante du fil passe en texte statique (couleur `#C9CDD4`, sans brillance) tant que la tâche n'est pas relancée ; elle est construite à partir du dernier message de l'assistant (champ `last_assistant_message` de l'événement Stop, nettoyé du Markdown par `DiffEngine.toOneLine` — premier paragraphe utile uniquement).

### Pastilles (overview)
- 132 × 34, rayon 17, fond couleur de l'agent à 13 %, bord à 32 %, mini-bonhomme Ø 24 centré à 17 pt du bord gauche, libellé 12 pt couleur de l'agent éclaircie de 25 %. Deux colonnes, écart 8, centrées verticalement dans la carte droite (qui commence à x = 342).

### Catalogue de pastilles
Toutes les pastilles déclarées sont définies dans `PillCatalog.all` (source de vérité unique). Quatre catégories :

| Catégorie | Titre | Pastilles | Subtitle (repos) | Subtitle (session) |
|---|---|---|---|---|
| `workspace` | Where you code | VS Code, Cursor, Antigravity *(GitHub only)*, Codex *(GitHub only)*, Claude *(app de bureau, GitHub only)* | Integration | Claude Code / Cursor / Codex / Claude / Agent |
| `agent` | Agents | Gemini CLI *(GitHub only)* | Agent | Agent |
| `ai` | AI for the chat | Anthropic, Google AI, OpenAI, DeepSeek, Ollama, LM Studio | Chat | — |
| `service` | Services | Resend, n8n, Vercel, GitHub, Notion, Cal.com, Stripe, Apple Music *(GitHub only)*, Mail *(GitHub only)*, ChatGPT *(raccourci, GitHub only)* | Integration (Mail, ChatGPT : App) | — |

Couleurs : Cursor `#C0C4CC`, Codex `#2DD4BF`, Gemini CLI `#8AB4F8`, Antigravity `#E879F9`, pastilles IA = `ChatProvider.accentHex` (Ollama `#FACC15`, LM Studio `#A3E635`).

Règles :
- **`mainPillId`** (défaut `integration_claude`) est la pastille workspace toujours chargée. Elle ne compte pas dans cette limite. Modifiable via le sélecteur Main dans Settings.
- Quand `mainPillId != "integration_claude"`, la pastille VS Code est chargée seulement si une session VS Code est active (transient) ou si elle est cochée dans `activeIntegrations`.
- Max 8 pastilles autres que `mainPillId` actives à la fois (`activeIntegrations`, persisté ; limite = `AppState.maxActivePills`).
- Carte de droite de `overview` : grille 2×2, 4 pastilles par page. Au-delà de 4, flèches ‹ › de chaque côté de la grille (grisées en première / dernière page, son `tick`). Une pastille avec badge sur une page cachée met un point de la couleur du badge sur la flèche qui y mène (priorité approval > error > finished). La grille compact et la colonne des autres vues montrent toujours les 4 premières.
- Focus temporaire (`AppState.focusForNotice`) : quand une pastille non focalisée reçoit une notification (fin ou erreur d'une session d'agent, workflow n8n, déploiement Vercel, paiement Stripe), elle prend le focus pendant 15 s (`noticeFocusDuration`) puis la pastille d'avant revient. Si l'île n'était pas ouverte, elle s'ouvre sur `overview` et se replie à la fin (`.noticeCollapse`), sauf autre vue ouverte ou approbation en cours ; si la souris est sur l'île, elle se replie 1,5 s après que la souris l'a quittée (annulé si elle revient). Plusieurs notifications d'affilée reviennent à la pastille d'origine. Au lancement, le premier relevé de chaque service (Vercel, n8n, Stripe, Mail) sert de point de départ et ne notifie jamais : seul ce qui se termine ou arrive après le lancement notifie. Vercel refait ce point de départ quand le filtre de projets change. La pastille notifiée garde son badge. Un clic sur une pastille annule le retour. Pas de focus temporaire pendant une carte d'approbation ; une approbation qui arrive pendant un focus temporaire rend ensuite le focus à la pastille d'origine.
- `removeTask` sur `mainPillId` ou une pastille déclarée + active → reset à `.idle` + `pillBadge = nil` + nom du catalogue (pas de suppression). Sinon → suppression normale.
- `sortTasksByCatalog` : pastilles du catalogue dans l'ordre du catalogue ; pastilles hors catalogue juste après `integration_claude`.
- Pastilles `githubOnly` : exclues des builds App Store (`#if APPSTORE`).
- Claude (app de bureau, `agent_claude_desktop`) : ses sessions Claude Code passent par les mêmes hooks que la CLI ; routage sur `bundle_id == com.anthropic.claudefordesktop`. Les demandes de permission ne s'affichent pas dans l'encoche (réponse « ask », l'app de bureau garde sa propre fenêtre). Configurée = hooks Claude Code installés.
- Mail (`integration_mail`) : `MailPoller` lit Mail par AppleScript toutes les 45 s, seulement si la pastille est active et Mail déjà ouvert (ne lance jamais Mail). Settings → Mail → Accounts : jusqu'à 2 comptes à surveiller (`mailAccountFilter`, `AppState.maxMailAccounts`) ; aucun = boîte de réception unifiée. Pour un compte, sa boîte est la boîte de premier niveau nommée INBOX (casse ignorée). Pour chaque boîte : nombre de non lus, puis les 5 premiers et 5 derniers messages (Message-ID, expéditeur, objet, âge en secondes, lu ou non), les plus récents gardés. La carte montre les 3 plus récents de la boîte affichée (`mailShownAccount`) ; avec 2 comptes, flèches ‹ › dans l'en-tête ; un clic sur un message l'ouvre (`message://<id>`). Premier relevé (et après un changement de comptes) = référence, sans notification ; ensuite, un nouveau message non lu → son compte devient la boîte affichée (jusqu'au prochain mail ou ‹ ›), état `.finished`, badge, focus temporaire avec ouverture de l'île même si Mail est déjà focalisée, émote surprise, son `pop` (une seule notification par relevé). Statut : « x unread » / « No unread mail » / « Mail not open » / « Automation not allowed » (erreur -1743, bouton « Open Settings… »). Rien ne quitte le Mac.
- ChatGPT (`integration_chatgpt`) : raccourci seulement (l'app n'envoie aucun événement). Un clic ouvre l'app (`com.openai.chat`, sinon `/Applications/ChatGPT.app`). Statut « Shortcut · opens the app » ou « App not installed ».
- Hooks (Gemini CLI, Antigravity, Codex) : `isConfigured` = `HookServer.geminiHooksInstalled()` / `agyHooksInstalled()` / `codexHooksInstalled()` sous `#if !APPSTORE`. La section Codex Hooks dans Settings installe les hooks dans `~/.codex/hooks.json` avec le même flux backup + preview que Gemini CLI. Après l'installation, la carte affiche : « run /hooks in Codex or open Hooks in the app's settings to trust them ». Approbations Codex : carte avec Allow et Deny seulement (pas Always) ; updatedPermissions jamais envoyé ; notes « Handled in Codex. » / « Still waiting in Codex. ».
- Pastilles IA (cloud) : `isConfigured` = clé API dans le Keychain. Pastilles IA locales (Ollama, LM Studio) : `isConfigured` = URL serveur non vide (définie via le bouton **Connect** dans Réglages → Chat). Bouton « Chat with… » → change le fournisseur et ouvre la vue `.prompt`.

### Carte GitHub (`GitHubPulseCardView`)

Affichée à la place de `GitHubStatsCardView` quand un `GitHubPulse` est disponible (`githubPulse != nil`). Trois lignes `GitHubStatRow` (My PRs, To review, Default branch CI), chacune tappable → ouvre `GitHubDetailView` avec la section correspondante. En-tête : point rouge + « GitHub » + bouton « ★ N.Nk » (étoiles) + rangée de 7 carrés de contribution (7 derniers jours, 7 pt, espacement 2 pt) si `githubActivity != nil` → ouvre la section `.activity`. Sans stats : « Overview ».

### Vue détail GitHub (`GitHubDetailView`)

Remplace la carte principale quand `showingDetail && githubHasPulse`. En-tête : chevron.left (← ferme) + titre de section. Sections **My PRs**, **To review** → `GitHubPRRowView` (point CI + « repo#N » + titre tronqué + badge Draft), ScrollView maxHeight 60 pt (3 lignes × 20 pt), fondu bas si > 3 éléments. Section **Default branch CI** → `GitHubRepoCIRowView` (point CI + nom court + branche + état). Clic sur une PR → ouvre `https://github.com/…` (filtré `host == "github.com"`). Échap ferme.

### Section Activity (`GitHubActivityDetailContent`)

Section `.activity` de `GitHubDetailView`. En-tête : chevron.left + « Activity » à gauche ; à droite (11 pt #8E939C) : « 1,234 past year · N repos » (clic → `github.com/<login>`). Au survol / clic sur un carré : texte remplacé par « Oct 3 · 12 contributions » (ou « 1 contribution », ou « No contributions »). Grille de contributions : colonnes = semaines (la plus ancienne à gauche, ~20 semaines à 8 pt avec espacement 2 pt), lignes = jours de la semaine (dimanche = ligne 0). Couleurs des niveaux : 0 = blanc 6 %, 1 = `#0E4429`, 2 = `#006D32`, 3 = `#26A641`, 4 = `#39D353`. Pas de ScrollView, `.clipped()`. `refreshActivityIfStale()` à l'apparition.

### Boutons
- Pilule, 12,5 pt medium, fond blanc 9 % (survol 15 %), primaire : fond `#F5F6F8` texte `#0B0C0E`. Appui : échelle 0,94. Raccourcis affichés en petite pastille bordée (Y, N).

## 6. Couleurs des agents (fixes)

| Agent | Couleur |
|---|---|
| Korus | `#FF6B5B` |
| SBE Hub | `#2DD4A7` |
| Morning AI Brief (n8n) | `#F7B32B` |
| Publication IG (n8n) | `#A78BFA` |
| louisraille.fr | `#38BDF8` |
| Autres | prendre dans cet ordre : `#F472B6`, `#34D399`, `#FB923C`, `#60A5FA`, `#E879F9`, puis boucler |

Nom d'une session Claude Code = nom du dossier de travail (`cwd`), avec une table d'alias réglable (ex. `sbe-hub` → « SBE Hub »). Nom d'un workflow n8n = nom du workflow.

## 7. Le personnage : Mochi

Porter la classe `Bot` du prototype **telle quelle** en Swift (`Canvas` dans `TimelineView(.animation(paused:))`). Constantes Mochi (`PISTES.mochi`) :

- R = 0,3 × côté du canvas. Corps : superellipse d'exposant 2,7, rayons rx = 1,14 R, ry = 0,88 R, décalé de +0,06 R vers le bas.
- Dégradé du corps : `#FFFAF5` (haut droite) → `#DDCCBF` (bas gauche). Teinte d'état : dégradé linéaire de bas en haut, couleur d'état à 92 % × tint jusqu'à transparent à −0,25 ry. Ombrage radial (bord 20 % noir) et reflet radial blanc 55 % en haut à droite.
- Joues : deux ellipses rose `rgba(255,120,150,.5 × blush)`, blush minimum 0,35 pour Mochi, suivent le regard.
- Yeux : encre `#1A1412`, largeur 0,25 R, hauteur 0,27 R, écart angulaire ±0,37 rad, inclinaison verticale −0,12 rad. Projection sur une sphère (yaw, pitch, roll) avec raccourci de perspective et découpe par la silhouette : c'est ce qui donne les roulades (les yeux sortent par le haut et reviennent par le bas).
- Regard : suit la souris avec retard (`tanh(dx/260)`, `tanh(dy/200)`, lissage exponentiel). Clignement aléatoire toutes les 2,2 à 5,4 s, double clignement 22 % du temps.
- Mini-bonhommes : même moteur, corps teinté de la couleur de l'agent, badges réduits.
- Canvas du gros bonhomme : 230 pt × 2 (Retina) ; mini : 76 pt × 2.

### États (`STATES`)

| Clé | Libellé | Couleur | Teinte | Yeux | Badge | Particularité |
|---|---|---|---|---|---|---|
| `idle` | Au repos | `#E6E9EE` | 0 | pilule | aucun | |
| `working` | Travaille | `#3B9EFF` | 0,72 | pilule | pilule « ••• » animée | |
| `thinking` | Réfléchit | `#8B5CF6` | 0,72 | pilule | « ••• » | regarde en haut à droite |
| `searching` | Cherche | `#6366F1` | 0,72 | pilule | « ••• » | yeux qui balaient de gauche à droite |
| `approval` | Attend ton feu vert | `#F5A524` | 0,78 | grands | « ! » | petits sauts en boucle |
| `question` | Pose une question | `#22D3EE` | 0,75 | pilule | « ? » | tête penchée 0,17 rad |
| `error` | Erreur | `#F4505E` | 0,78 | plats | point rouge | secousse horizontale à l'entrée |
| `finished` | Terminé | `#34D399` | 0,35 | contents (arc) | point vert | roulade complète 950 ms + étincelles |
| `ratelimit` | Limite atteinte | `#FB923C` | 0,72 | fatigués | point orange | gouttes de sueur |
| `sleeping` | Dort | `#94A3B8` | 0,32 | fermés | aucun | respiration, « z » qui montent |
| `dizzy` | Sonné | `#F472B6` | 0,7 | spirales | aucun | double roulade 1,3 s |

Halo derrière le bonhomme : dégradé radial couleur de l'état, opacité 0,2 à 0,6 selon l'état (`glow`, `go`), flou 6.

Correspondance avec les vrais événements : voir `INTEGRATIONS.md`. `sleeping` = aucune tâche depuis 10 min et island ouverte manuellement ; `ratelimit` = limite d'usage signalée par Claude Code.

### Émotes (`EMOTES`) et déclencheurs réels

| Émote | Yeux | Extra | Son | Déclencheur |
|---|---|---|---|---|
| Amour | cœurs `#FF4D6D` | joues à fond, cœurs qui montent | `love` | souris immobile 1,9 s sur le bonhomme |
| Surpris | petits points | saut + yeux agrandis | `pop` | quand on l'attrape |
| Fier | étoiles `#F7B32B` | étoiles, tête en arrière | `proud` | résultat de recherche affiché |
| Clin d'œil | un œil fermé | tête penchée | `wink` | mail envoyé, fenêtre attrapée |
| Bâille | fatigués puis fermés | étirement vertical, « z » | `yawn` | juste avant de passer en `sleeping` |
| Content | arcs | joues | — | après une décision, un fichier avalé |
| Agacé | fentes inclinées | halo violet `#A855F7` | `annoyed` | une claque |

## 8. Interactions avec le bonhomme

- **Survol** (expanded) : clignement, yeux ×1,08, son `hover`. Immobile 1,9 s → Amour.
- **Clic** en compact/peek → ouvre. **Clic** en expanded → claque : écrasement (70/130/170 ms), Agacé 800 ms, halo violet, sons `slap` + `annoyed`.
- **3 clics en moins de 1,7 s** → état `dizzy` pendant 3,3 s, vue `confused`, son `dizzy`, puis retour à la vue et à l'état d'avant.
- **Glisser** le bonhomme (> 7 pt) : un bonhomme flottant Ø 54 suit le curseur (Surpris + `pop`), celui du notch disparaît. Lâché sur une fenêtre d'une autre app → **attache** (voir INTEGRATIONS §4). Lâché ailleurs → revient dans le notch en 420 ms en rétrécissant.
- **Glisser un fichier** depuis le Finder vers la zone du notch (±220 pt autour du centre, jusqu'à 26 pt sous l'island) → vue `upload`, le bonhomme se transforme en « bac » (morph 380 ms avec rebond) et regarde le fichier. Contour vert et voile vert quand le fichier est au-dessus.
- **Déposer** : le fichier file dans le bonhomme (360 ms), `gulp` à 330 ms, écrasement + Content, retour à la forme ronde à 950 ms, vue `uploading` (1,2 à 2,1 s, `tick` tous les 10 %, correspond à la copie dans le dossier de travail de l'app), son `approve`, puis vue `choose`.
- Plusieurs fichiers : même flux, libellé « 3 fichiers ».

## 9. Sons

Fichiers `assets/sounds/*.wav` (48 kHz stéréo), rendus depuis le moteur du prototype avec un gain ×6. **Volume par défaut du lecteur : 0,12** pour retrouver le niveau du prototype ; le curseur de volume des réglages va de 0 à 0,2. Jouer avec `AVAudioPlayer` préchargés (latence nulle), plusieurs sons peuvent se superposer. Désactivable dans l'en-tête de l'island et dans les réglages (persisté).

| Événement | Son |
|---|---|
| peek / coucou | `peek` + `greet` |
| ouverture / fermeture | `open` / `close` |
| survol du bonhomme / petit clic UI | `hover` / `blip` |
| claque / agacé / sonné | `slap` / `annoyed` / `dizzy` |
| travaille / réfléchit / cherche | `work` / `think` / `search` |
| permission / question / erreur / limite | `approval` / `question` / `error` / `rate` |
| terminé | `finish` |
| décision validée, upload fini | `approve` |
| fichier avalé / progression | `gulp` / `tick` |
| envoi (prompt, mail) / attache fenêtre | `send` / `attach` |
| émotes | `love`, `pop`, `proud`, `wink`, `yawn`, `sleep` |

Pas de son pour les mises à jour silencieuses (défilé de tâches, mini-bonhommes qui changent d'état sauf alerte).

### Voix (Coucou parle)

`VoiceEngine` parle de deux façons, rien ne sort du Mac. Désactivé par défaut.
- **Voix Mochi** (choix par défaut, identifiant vide) : répliques enregistrées dans `Resources/voice/` (créées avec ElevenLabs, converties en WAV 48 kHz stéréo, silences coupés, volume égalisé). Une réplique = `nom.wav` ou des variantes `nom-1.wav`, `nom-2.wav`… tirées au hasard, jamais deux fois la même d'affilée. Elle démarre 0,45 s après le son de l'événement. Mochi hoche la tête à chaque remontée du volume (mesure du lecteur, 30 Hz, seulement pendant la réplique). Événement sans réplique → voix du Mac. Les WAV restent hors de git (`.gitignore`, voir `Resources/voice/README.md`) : sans eux, « Mochi » disparaît du choix et la voix du Mac prend le relais.
- **Voix du Mac** (`AVSpeechSynthesizer`) : « System voice » ou une voix choisie. Lit aussi les réponses du chat en mode Mochi. Les phrases suivent la langue de la voix : français pour une voix `fr-*` (et pour Mochi), anglais sinon.

Répliques de Mochi :
- agents : `fini` (fin), `erreur` (échec), `feu-vert` (permission), `question` (question, sans lire la question), `limite` (limite d'usage) ;
- services (réglage « Services ») : `deploy-ok` / `deploy-erreur` (Vercel), `ci-ok` / `ci-erreur` / `review` (GitHub pulse, l'événement le plus important d'un relevé), `paiement` (Stripe), `mail` (nouveau mail), `mail-envoye` (mail envoyé depuis le notch). Sans réplique → voix du Mac (« Nouveau paiement : 49 € ») ;
- réactions (réglage « Mochi's reactions », voix Mochi seulement, jamais la voix du Mac) : `coucou` (accueil au lancement et au retour d'absence, pas à chaque survol), `claque` (claque, sauf la 3e), `sonne` (sonné après 3 claques), `amour` (souris immobile sur Mochi), `fier` (résultat de recherche), `fichier` (fichier avalé). `baille` attend un déclencheur : l'état `sleeping` n'est jamais activé.

Les répliques s'ajoutent aux sons de Coucou, elles ne les remplacent pas. Priorité : alertes d'agent > services et chat > réactions ; une nouvelle réplique coupe celle en cours sauf si celle-ci est prioritaire. Le nom annoncé est celui du dossier de l'événement (avec alias), pas celui de la pastille, partagée entre sessions.

| Événement | Phrase (voix française) | Réglage |
|---|---|---|
| fin de session (`Stop`) | « projet a terminé. » | When an agent finishes or fails |
| échec (`StopFailure`) | « projet a rencontré une erreur. » | idem |
| permission | « projet attend ton feu vert. » | Permissions and questions |
| question (`AskUserQuestion`) | « projet te pose une question. » + texte de la 1re question | idem |
| limite d'usage (`Notification` rate limit) | « projet a atteint sa limite d'usage. » | When an agent finishes or fails |
| réponse du chat | la réponse sans Markdown (code, liens, emphase retirés), coupée à la fin de phrase avant 600 caractères | Chat answers (off par défaut) |

- Une alerte coupe ce qui est en cours ; une réponse du chat ou un service ne coupe jamais une alerte ; une réaction ne coupe jamais rien d'autre qu'une réaction.
- Carte de permission ou de question répondue ou fermée → l'annonce s'arrête. Nouvelle question au chat → l'ancienne réponse s'arrête. `Échap` island ouverte → silence.
- Pendant la parole, Mochi fait un petit hochement à chaque mot (`speakBob`, notification `.botSpeakWord`), sauf pendant une animation plus grande.
- La voix ne valide jamais une permission : on lit la demande, la réponse reste un clic.

## 10. Barre de menus et réglages

Petit item dans la barre de menus (icône : silhouette du Mochi, monochrome). Menu : Ouvrir le notch, Lancer la démo (⌃⌥⌘D), Réglages…, Debug ▸ (forcer chaque vue, chaque état, chaque émote, ajouter des tâches factices), Quitter.

Fenêtre Réglages (SwiftUI, simple), sections dans l'ordre d'affichage :
- **Anthropic API** : clé (Trousseau), modèle (défaut `claude-sonnet-4-6` ; liste depuis l'API, voir INTEGRATIONS §5).
- **Chat — other providers** : clé Google AI (Trousseau) ; clé OpenAI (Trousseau) ; clé DeepSeek (Trousseau). Les modèles se choisissent dans le chat (voir INTEGRATIONS §5bis).
- **Local models** : URL du serveur Ollama (défaut `http://127.0.0.1:11434`) et/ou LM Studio (défaut `http://127.0.0.1:1234`). Bouton **Connect** : vérifie la joignabilité et sauvegarde l'URL. Bouton **Disconnect** : efface l'URL et le cache. Aucune clé requise (voir INTEGRATIONS §5ter).
- **Claude Code Hooks** : état des hooks, bouton Installer / Désinstaller.
- **Plan usage** : toggle **Show in the notch** + bouton **Install relay** / **Uninstall relay**. Voir INTEGRATIONS §1bis. **Jauge de forfait Claude** *(GitHub only)* : petit pill dans l'en-tête de l'île (vue home uniquement). Activé via `showPlanInNotch` (UserDefaults) + `HookServer.statusLineInstalled()`. Couleur = `ClaudePlanGauge.color(for: dominantPct)`. Clic → `showingPlanDetail` bascule et `ClaudePlanCardView` s'affiche à la place de la carte en cours. `showingPlanDetail` se remet à false au changement de focusId, de vue ou de mode. Grand Mochi prend la couleur de l'usage quand `showingPlanDetail == true`.
- **Gemini CLI Hooks** *(build GitHub)* : état des hooks, bouton Installer / Désinstaller.
- **Antigravity Hooks** *(build GitHub)* : état des hooks, bouton Installer / Désinstaller.
- **Integrations** : clé ou token (Trousseau) pour chaque service (n8n, Stripe, GitHub, Vercel, Resend, Notion, Cal.com).
- **Sound** : son on/off, volume.
- **Voice** : Coucou speaks on/off, choix de la voix (« Mochi » = répliques enregistrées, « System voice » = voix système de la langue, puis les voix du Mac des langues de l'utilisateur + anglais, sans voix fantaisie, meilleure qualité d'abord), bouton Test, et ce qui est lu : fin/échec d'agent, permissions et questions, réponses du chat. Voir §9.
- **Behavior** : fermeture après N s d'inactivité ; masquage après N min sans mouvement.
- **Active pills** : pastilles actives (VS Code toujours actif + jusqu'à 4 autres) ; sélecteur de pastille principale (affiché uniquement si une pastille workspace est active) ; liste par catégorie (voir catalogue §5).
- **Hotkey** : raccourci global pour ouvrir le notch, et le refermer s'il est ouvert (sauf carte épinglée). Enregistré auprès du système (`RegisterEventHotKey`, `GlobalHotKey.swift`) : aucune autorisation Accessibilité, marche dans le bac à sable App Store, et la touche ne va qu'à Coucou (l'app au premier plan ne la reçoit pas, donc éviter les raccourcis courants comme ⌘O). Suspendu pendant l'enregistrement d'un nouveau raccourci dans Réglages.
- **Startup** : lancer au démarrage (`SMAppService.mainApp`).

## 11. Jalons

Chaque jalon se termine par build + capture + comparaison aux références + commit (voir CLAUDE.md).

- **M0 Base** : vérifier Xcode (`xcodebuild -version`), XcodeGen, `git init`, `project.yml`, app agent qui se lance et affiche le faux contenu. Menu Debug.
- **M1 Island** : panel, détection du notch, 4 modes, règles §3, clics traversants, animations §4, données factices.
- **M2 Personnage** : port de `Bot` (Mochi), tous les états et émotes, mini-bonhommes, halo, badges, particules, mains. Pause quand masqué.
- **M3 Vues** : toutes les vues §5, défilé, pastilles, colonne, élément partagé, voiles. Comparer avec les 16 captures.
- **M4 Sons** : branchement §9, réglages son.
- **M5 Claude Code** : hooks, approbations, questions, saut au terminal (INTEGRATIONS §1).
- **M6 n8n** : polling, erreurs, relance, ouverture (INTEGRATIONS §2).
- **M7 Fichiers** : glisser-déposer, prompt sur fichier, mail via Mail (INTEGRATIONS §3 et §6).
- **M8 Fenêtres + recherche** : attache, capture, URL, API Claude avec recherche web, vue résultat (INTEGRATIONS §4 et §5).
- **M9 Finition** : mode démo (DEMO.md), réglages complets, lancement au démarrage, écran sans notch, mesure CPU/RAM, passe finale de comparaison visuelle.

## 12. Critères d'acceptation

- Côte à côte avec le prototype, Louis ne voit pas de différence sur le personnage, les couleurs, les timings et les sons.
- Aucun clic perdu à cause de la fenêtre transparente.
- Une session Claude Code n'est jamais bloquée par l'app (app fermée, plantée ou lente → le terminal prend le relais).
- Hidden = 0 % CPU ; compact < 3 % ; mémoire < 100 Mo.
- La démo (⌃⌥⌘D) se filme d'une traite sans intervention.

