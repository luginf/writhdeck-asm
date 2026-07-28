# CLAUDE.md — writhdeck-asm (x86-linux)

Portage x86 assembleur (FASM, syntaxe Intel) de WrithDeck, à partir de
la logique déjà portée en C dans [`../writhdeck-c`](../writhdeck-c).
Zéro libc, zéro toolchain C, syscalls Linux directs (`int 0x80`). Voir
`README.md` pour le périmètre fonctionnel exact (ce qui est implémenté,
ce qui est délibérément hors périmètre) et les instructions de build.
Ce fichier documente les pièges rencontrés en travaillant sur ce code
et les conventions à connaître avant d'y toucher.

## Convention d'appel

cdecl minimal (`src/macros.inc`) : arguments empilés droite-à-gauche,
l'appelant nettoie la pile. Retour dans `eax`.

**Seuls `ebx`/`esi`/`edi`/`ebp` sont préservés par l'appelée.**
`eax`/`ecx`/`edx` sont caller-saved et peuvent être écrasés par
n'importe quel `call`, y compris un `call` qui semble anodin. C'est la
source de bugs la plus récurrente rencontrée sur ce projet — voir
ci-dessous.

## Pièges rencontrés (à vérifier avant de toucher du nouveau code)

### 1. `ecx` écrasé par les appels systeme / `strlen`

`sys_read`/`sys_write`/`sys_open` (`buffer.asm`) chargent `ecx` avec un
argument du syscall lui-même ; `strlen` (`strutil.asm`) utilise `ecx`
comme compteur interne de `repne scasb`. **Ne jamais garder un état de
boucle dans `ecx` (ou `eax`/`edx`) à travers un `call` vers l'une de
ces fonctions ou vers tout ce qui les appelle transitivement** — utiliser
`ebx`/`esi`/`edi` ou une variable locale sur la pile, et si besoin
relire l'argument directement depuis `[ebp+N]` après l'appel plutôt que
de faire confiance à un registre.

Rencontré concrètement à deux reprises :
- `ui_ansi.asm:ui_read_event`, boucle `.num_loop` qui parse
  `ESC[<chiffres>~` (Home/End/PgUp/PgDn/Delete/F11) : accumulait le
  nombre dans `ecx` à travers des `call term_read_byte` répétés →
  résultat garbage, plantait silencieusement PgUp/PgDn/Delete (jamais
  testés avec un vrai flux d'octets) et le F11 nouvellement ajouté.
  Corrigé en utilisant `ebx` comme accumulateur.
- `draw.asm:st__tok_is` (dispatch de tokens de barre de statut) :
  chargeait `tok_len` dans `ecx` juste avant `call strlen` → toutes les
  comparaisons de tokens échouaient silencieusement, la barre de statut
  affichait les noms de tokens tels quels ("workspacefilenamedirty...")
  au lieu de les interpréter. Corrigé en relisant `[ebp+12]` après
  l'appel plutôt que de faire confiance à `ecx`.

**Symptôme typique : pas de crash, un résultat silencieusement faux.**
Aucun test n'existant dans ce projet ne pousse de vrai flux d'octets à
travers `ui_read_event`, donc cette classe de bug n'a pas de garde-fou
automatique côté clavier — être particulièrement prudent en y touchant.

### 2. Largeur de wrap : `draw_editor` et `editor_move_up/down` DOIVENT s'accorder

`draw.asm:draw_editor` dessine et enroule le texte à `text_width = cols
- 2*g_cfg_margin_cols` (marges par défaut 6 colonnes de chaque côté,
voir `config.asm`), jamais la largeur brute du terminal.
`editor_move_up`/`editor_move_down` (`editor.asm`) recalculent
indépendamment le word-wrap (via `editor_wrap`) pour savoir sur quelle
ligne VISUELLE se trouve le curseur — ils doivent donc être appelés
avec **exactement la même largeur ajustée des marges**, sinon le
curseur "saute" sur une rangée visuelle différente de celle affichée
dès que des marges sont actives (bug réel : `main.asm` passait `g_cols`
brut à Haut/Bas après l'ajout des marges, jamais corrigé pendant le
merge — voir `writhdeck-c/src/main.c`, qui recalcule explicitement
`ud_text_width` avant CHAQUE appel à `editor_move_up`/`editor_move_down`
pour cette raison précise). Corrigé ici via `main.asm:ud_text_width`,
appelée dans `.do_up`/`.do_down` avant `editor_move_up`/`editor_move_down`.

**Comment appliquer :** tout nouveau point d'appel qui a besoin de
savoir sur quelle rangée VISUELLE (enroulée) se trouve du texte doit
utiliser cette même largeur ajustée des marges (`ud_text_width(cols)`
côté `main.asm`, formule identique à `draw_editor`) — jamais `[g_cols]`
directement. Aucun test ne pousse Haut/Bas à travers le vrai dispatch
de `main.asm` avec des marges non nulles, donc cette classe de
régression ne serait pas détectée automatiquement.

### 3. Le Makefile ne suit PAS les dépendances `include` de FASM

`Makefile` : `$(BIN_DIR)/%: $(TESTS_DIR)/%.asm | $(BIN_DIR)` — la seule
dépendance déclarée est le fichier `.asm` du test lui-même, jamais les
fichiers qu'il `include`. Modifier `src/draw.asm` (inclus par
`test_draw.asm`, `test_config.asm`, `main.asm`...) **ne déclenche PAS**
la recompilation de ces binaires via `make test`/`make writhdeck` si
leur timestamp est plus récent que celui du fichier `.asm` source
modifié récemment mais plus ancien que le binaire déjà présent dans
`bin/`. Résultat observé concrètement : un fix appliqué dans
`draw.asm` semblait ne rien changer au comportement du binaire testé,
alors que le fix était correct — le binaire testé était simplement
resté celui d'avant.

**Toujours faire `make clean` avant `make test`/`make writhdeck` après
avoir modifié un fichier `.inc` ou un `.asm` inclus par d'autres**
(à peu près tout sauf un fichier `test_*.asm` lui-même) — ou invoquer
`fasm` directement sur le(s) binaire(s) concerné(s) pour un cycle plus
rapide en cours de debug, mais ne jamais conclure "le fix ne marche
pas" sans avoir d'abord forcé une recompilation propre.

### 4. `UIK_CTRL_R` (remplacer) est deja decode mais pas cablee -- meme etat que `UIK_CTRL_F` avant son ajout

`ui_ansi.asm:618` decode deja Ctrl+R (`UIK_CTRL_R`) et `editor_replace_all`
(`editor.asm`, deja teste dans `test_editor.asm`) existe et fonctionne --
mais rien dans `main.asm` ne dispatche cet evenement, donc Ctrl+R ne
fait actuellement rien. C'etait exactement l'etat de Ctrl+F avant son
cablage (voir section suivante) : facile a confondre avec "non
implemente" alors que la brique la plus couteuse (la logique metier)
est deja portee et testee. Pour le cabler, suivre le meme patron que
`.do_find`/`prompt_line` dans `main.asm` : `prompt_line` pour le terme
a chercher, un second `prompt_line` (nouveau libelle, ex. "Replace
with: ") pour le remplacement, verifier au moins une occurrence
(`ascii_stristr` sur chaque ligne) avant `editor_push_undo` (undo
seulement empile s'il y a effectivement un remplacement, meme
convention que le C, `main.c:704-720`), puis `editor_replace_all` +
message du nombre de remplacements via `show_message`.

## Ecart fonctionnel avec writhdeck-c (etat courant, a tenir a jour)

Vue d'ensemble pour reprendre le travail sans re-derouler toute
l'exploration -- le detail de ce qui EST porte (touches, `.ini`
partiel) reste dans `README.md`, section correspondante.

**Cout faible, brique deja portee (voir piege #4 ci-dessus) :**
- Ctrl+R (remplacer) -- `editor_replace_all` existe et est teste, il
  ne manque que le cablage UI.

**Fonctionnalites du C absentes de ce portage :**
- Navigateur de fichiers (`browser.c`) -- lister/filtrer/ouvrir/creer/
  renommer un fichier dans un dossier. Ce portage n'ouvre que
  `argv[1]` (ou un brouillon vide), aucune UI de navigation.
- Etat persistant / statistiques (`state.c`, `~/.writhdeck.json`) --
  fichiers recents, position du curseur restauree par fichier, compte
  de mots quotidien avec ecran de stats (`show_stats`, touche `s` du
  mode commande cote C). Chaque session de ce portage repart de zero.
- Minuteur / Pomodoro (`timer.c`) -- demarrage/pause/reset, alerte
  plein ecran + bip a expiration. Absent (le token de statut `clock`,
  simple heure courante, EST porte -- ne pas confondre les deux).
- Autosave / watch-file -- pas de sauvegarde periodique en tache de
  fond, pas de detection de modification externe du fichier avec
  proposition de recharger.
- Mode commande modal (Echap -> q/s/t/p cote C, `main.c:608-634`) --
  Echap n'est utilise ici que pour annuler les invites (Save as/Find/
  confirmation), pas comme entree d'un sous-mode quitter/stats/
  minuteur.
- i18n -- anglais uniquement, pas de bascule de langue (le C a un
  systeme de locale complet dans `i18n.c`).

**Deja au parite avec le C (pour eviter de re-verifier inutilement) :**
undo/redo (meme plafond 100 entrees), UTF-8 complet, coloration
syntaxique + table des matieres (F11), une bonne partie du `.ini`
(marges, objectif de mots, tokens de barre de statut -- voir README
pour le sous-ensemble exact des cles reconnues), Ctrl+F (recherche,
ajoutee dans cette session).

## Où regarder pour le contexte fonctionnel

- `README.md` : périmètre exact, touches supportées, format `.ini`
  reconnu, tests disponibles.
- `../writhdeck-c` : référence de portage — en cas de doute sur un
  comportement, le C fait autorité (ce portage vise la fidélité au C,
  avec des simplifications explicitement documentées dans le README
  quand une fonctionnalité C est hors périmètre).
