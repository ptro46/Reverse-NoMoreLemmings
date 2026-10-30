# Oh No! More Lemmings — reconstruction native Mac

Application Swift / AppKit pour Mac Apple Silicon, macOS 13 ou ultérieur. Le jeu utilise les ressources extraites de `ohno.adf`. Le disque original reste inchangé.

## Correctif 0.1.1

Le creusement efface désormais les quatre composantes RGBA des pixels. Cela corrige les trous invisibles du tunnelier, du mineur et du foreur (et de l’explosion). Un test compose le terrain sur un fond noir avec le même format CoreGraphics que le jeu et vérifie les pixels creusés pour les trois compétences. Le défaut a été reproduit avant correction ; les tests passent après correction. Quitter puis rouvrir l’application pour charger la nouvelle version.

## Jouer

Ouvrir `build/Lemmings Mac.app` dans le Finder, ou lancer `Lancer Lemmings.command`.

- Les 100 niveaux de la campagne sont disponibles dans le menu, répartis entre Tame, Crazy, Wild, Wicked et Havoc.
- Choisir une compétence, puis cliquer sur un lemming. Les touches 1 à 8 sélectionnent les compétences.
- Espace : pause ; F : vitesse ×4 ; R : recommencer ; Entrée : continuer après le résultat.
- Flèches, molette et mini-carte : déplacement de la vue.
- Le débit règle la fréquence d’apparition. Le bouton d’explosion générale arrête les entrées et amorce les bombes.
- Les cases Musique et Sons permettent de couper séparément les deux. Les réussites sont enregistrées dans les préférences locales.

## Contenu livré

- `Sources/` : moteur natif, terrain destructible, collisions, compétences, interface AppKit, rendu CoreGraphics et audio AVFoundation.
- `Assets/raw/` : 73 ressources extraites, sans modification.
- `Assets/decoded/` : programme, tables, 28 groupes de quatre niveaux, quatre jeux de terrains, quatre jeux d’objets et six partitions, décompressés avec contrôle du checksum ByteKiller.
- `Assets/images/` : six images IFF converties en PNG.
- `Assets/audio/` : 38 échantillons IFF convertis en WAV, comprenant effets et instruments.
- `Assets/game/` : catalogue des 100 niveaux dans l’ordre du jeu, terrains assemblés en PNG, masques de collision, 225 éléments de terrain, 376 images d’objets et 362 images d’animation de personnages.
- `Assets/music/` : les six morceaux rendus en WAV stéréo 44,1 kHz, puis encodés en M4A pour l’application. Le manifeste indique les durées, entre 37 et 56 secondes par boucle.
- `tools/` : scripts reproductibles d’extraction, de décompression, de conversion graphique et de rendu musical.

Le moteur de jeu fonctionne en Swift et ne contient pas d’émulateur Amiga. Pour convertir les musiques, l’outil de préparation exécute hors ligne le lecteur 68000 original avec machine68k/Musashi, puis reproduit les registres audio Paula, les instruments, les périodes et les boucles. L’application lit les fichiers audio obtenus avec AVFoundation. Le filtrage analogique de l’Amiga est approximatif.

## Compiler et vérifier

Les outils de développement Apple suffisent pour compiler ; aucun paquet Python n’est nécessaire pour jouer ni reconstruire l’application à partir des ressources déjà préparées.

```sh
cd /Users/ptro/Projets/Lemmings
./build.sh
"build/Lemmings Mac.app/Contents/MacOS/LemmingsMac" --self-test
```

La compilation utilise un cache local `work/ModuleCache`. Le bundle est signé localement, sans notarisation ni publication.

Les tests couvrent le chargement des 100 niveaux, 50 000 pas de simulation, la conservation des populations, la cohérence entre terrain et collisions, les entrées, la chute et l’atterrissage, les huit compétences, le creusement, l’acier, le retournement par un bloqueur, une sortie originale, la pause et la fin du temps. L’application a également été ouverte et contrôlée visuellement sur le Mac ; des lemmings ont atteint la sortie du premier niveau.

## Régénérer les ressources

Les dépendances des convertisseurs sont dans `tools/requirements.txt` ; Capstone sert seulement à l’outil de désassemblage.

```sh
python3 -m venv .venv
.venv/bin/pip install -r tools/requirements.txt
python3 tools/extract_adf.py ohno.adf Assets
python3 tools/decode.py
.venv/bin/python tools/convert_assets.py
.venv/bin/python tools/render_music.py
.venv/bin/python tools/encode_music.py
./build.sh
```

Le rendu musical nécessite également FFmpeg pour la copie M4A ; les WAV restent disponibles pour une utilisation indépendante.

## État et limites

Il s’agit d’une première version jouable, pas encore d’une reproduction certifiée à l’identique. Les huit compétences, le terrain modifiable, les sorties, dangers, zones d’acier et flèches à sens unique sont implémentés. Les timings et certains détails des collisions, des compétences et des pièges sont reconstruits ; la résolution de chacun des 100 niveaux et la fidélité des solutions Amiga n’ont pas été validées. Les animations de mort et les effets sonores ne couvrent pas encore toutes les variantes originales. Le mode deux joueurs n’est pas implémenté ; ses blocs de données restent extraits dans les fichiers bruts et décompressés. La présentation des menus est native Mac.

Crédits du jeu d’origine : DMA Design / Psygnosis, 1991. Les ressources proviennent uniquement du disque fourni. Outils de recherche consultés : [ancient](https://github.com/temisu/ancient) pour le format ByteKiller ; [machine68k](https://github.com/cnvogelg/machine68k) pour le rendu musical hors ligne.
