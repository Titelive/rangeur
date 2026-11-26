# Rangeur

Une app Mac pour trier ses Téléchargements comme sur Tinder : une carte par fichier, avec son aperçu, et un swipe pour décider.

| Souris / trackpad | Clavier | Action |
|---|---|---|
| Glisser à droite | → ou D | Ranger dans la catégorie proposée (Images, Documents…) |
| Glisser à gauche | ← ou Q | Garder le fichier dans Téléchargements (il ne sera plus reproposé) |
| Glisser vers le haut | ↑, Z ou ⌫ | Mettre à la corbeille (récupérable) |
| Bouton de catégorie | 1 à 9 | Ranger dans une autre catégorie |
| | Espace | Aperçu en grand (Quick Look) |
| Double-clic sur la carte | Entrée | Ouvrir le fichier |
| | U ou ⌘Z | Annuler le dernier tri (ou renommage) |
| ✏️ sur la carte | R | Renommer toi-même |
| ✨ sur la carte | I | Demander un nom plus clair |
| Bouton « Utiliser » | N | Accepter le nom proposé |

Les fichiers sont rangés dans les vrais dossiers du Mac :

| Catégorie | Touche | Dossier |
|---|---|---|
| Images | 1 | `~/Pictures` (Images) |
| Documents | 2 | `~/Documents` |
| Vidéos | 3 | `~/Movies` (Films) |
| Musique | 4 | `~/Music` |
| Archives | 5 | `Téléchargements/Archives` |
| Installeurs | 6 | `Téléchargements/Installeurs` |
| Code | 7 | `~/Documents/Code` |
| Jeux | 8 | `~/Games` |

Chaque dossier se change dans « Catégories » (bouton « Choisir… »). Un nom simple (« Archives ») crée un sous-dossier dans le dossier trié. Si un fichier du même nom existe déjà, Rangeur ajoute « (2) ». « Annuler » (U ou ⌘Z) remet le fichier exactement où il était, et la corbeille est celle du Mac.

**Jeux.** Les ROM et jeux (NSP, XCI, NSZ, 3DS, NDS, GBA, WBFS, RVZ, CSO, CHD…) sont proposés dans Jeux. Une archive ou une image disque dont le nom parle de jeu (« Zelda Switch NSP.rar », « … PS2.iso », « … FitGirl Repack.zip ») aussi, plutôt que dans Archives. Les mots-clés se modifient dans « Catégories ».

À la mise à jour, les catégories de base qui rangeaient dans `Téléchargements/Images`… passent aux vrais dossiers (sauf si tu avais changé leur dossier), et Jeux est ajoutée. Les fichiers déjà rangés restent où ils sont.

**Trier n'importe quel dossier.** Par défaut Rangeur trie Téléchargements, mais tu peux choisir un autre dossier :
- avec le menu à côté du titre, en haut de l'écran « À trier » (Téléchargements, Bureau, Documents, dossiers récents) ;
- avec **⌘O** ;
- en glissant un dossier du Finder sur la fenêtre.

Les sous-dossiers de catégories (Images, Documents…) sont alors créés à l'intérieur du dossier choisi.

**Les dossiers aussi.** Les dossiers présents dans le dossier trié apparaissent comme des cartes, avec une mosaïque de leur contenu, le nombre de fichiers et leur taille. Avec **Espace**, tu vois la liste complète de ce qu'ils contiennent. Un dossier est proposé dans la catégorie de la majorité de ses fichiers (un dossier de photos → Images), sinon dans « Dossiers ». Le mode automatique ne déplace jamais de dossier.

**Notifications.** Rangeur te prévient quand de nouveaux fichiers sont à trier (bouton « Trier maintenant »), et quand le mode automatique a rangé des fichiers (bouton « Annuler »). Une pastille sur l'icône du Dock indique le nombre de fichiers en attente. Tout se règle dans Réglages → Notifications. Les notifications ne fonctionnent qu'avec l'app installée par `build.sh`, pas lancée depuis Xcode.

**Renommage intelligent.** Les noms peu clairs (`IMG_6071.HEIC`, `6BDA7570-20C0….png`, `document (3).pdf`…) sont analysés automatiquement : Rangeur lit le contenu (texte, PDF, texte présent dans les images, site d'origine du téléchargement) et propose un meilleur nom sur la carte. Avec Apple Intelligence (macOS 26, Mac compatible), la proposition est faite par l'IA d'Apple, directement sur le Mac : rien n'est envoyé sur Internet. Sinon, Rangeur utilise des règles simples (titre du PDF, date de la photo…). Tu acceptes avec **N**, tu modifies avec **R**, et **⌘Z** annule. Option : appliquer automatiquement les noms proposés au moment de ranger. **Dates intelligentes** : les factures, reçus et devis commencent par la date lue dans le document (`2026-10-28 Facture EDF.pdf`), les bulletins de paie par le mois de la période (`2026-10 Bulletin de paie Acme.pdf`).

**Exceptions.** Dans Réglages → Exceptions, ajoute des motifs (`.torrent`, `Facture*`, `*devis*`) que Rangeur ne doit jamais proposer, ou jamais renommer. La liste des fichiers gardés d'un swipe à gauche y est aussi, avec un bouton pour les reproposer.

**Règles automatiques.** Écran « Règles » : « quand un fichier [Installeurs, Archives, un motif, un fichier gardé…] est là depuis [n jours / tout de suite], alors [corbeille, le ranger, le déplacer dans un dossier, me le reproposer] ». Modèles prêts à l'emploi, dont des règles malines : archives déjà décompressées, doublons exacts, fichiers vides, téléchargements abandonnés, gros fichiers oubliés. Les règles tournent au lancement puis toutes les heures, avec un aperçu des fichiers concernés ; tout passe par la Corbeille et s'annule.

**Statistiques.** Décisions, fichiers rangés, espace libéré, série de jours, activité par jour, répartition par catégorie, tes swipes en pourcentage, et quelques records.

## Installer

Il faut macOS 13 (Ventura) ou plus récent, et Xcode. Pour l'IA d'Apple : macOS 26 et Xcode 26.

1. Décompresse le dossier `Rangeur`.
2. Dans le Terminal, va dans le dossier puis lance :
   ```bash
   ./build.sh --install
   ```
   L'app est compilée, installée dans `/Applications` et lancée.
   (Sans `--install`, elle est juste créée dans `build/Rangeur.app`.)
3. Au premier lancement, macOS demande l'autorisation d'accéder au dossier Téléchargements : accepte.

## Modifier le code dans Xcode

Ouvre `Package.swift` avec Xcode (double-clic, ou `xed .` dans le dossier), puis ⌘R pour lancer.
Depuis Xcode, tout fonctionne sauf l'option « Ouvrir à l'ouverture de session », qui a besoin de la vraie app créée par `build.sh`.

## Les écrans

- **À trier** : la pile de cartes. Se met à jour toute seule quand un téléchargement se termine.
- **Activité** : l'historique de ce qui a été rangé, avec un bouton « Annuler » par fichier et « Tout ranger d'un coup ».
- **Règles** : les règles automatiques (au bout de n jours, fais…).
- **Catégories** : les catégories, leur dossier et leurs extensions (modifiables, on peut en ajouter).
- **Réglages** : le dossier à trier, le rangement automatique (optionnel, désactivé par défaut), l'ouverture au démarrage.

Fermer la fenêtre ne quitte pas l'app : une icône reste dans la barre des menus et indique s'il y a des fichiers à trier.

## Sécurité

- Les téléchargements en cours (`.crdownload`, `.download`, `.part`…) ne sont jamais touchés.
- Rien n'est supprimé définitivement : la corbeille reste la Corbeille du Mac.
- Les dossiers ne sont jamais déplacés automatiquement, seulement quand tu le décides.

## Structure

```
Sources/Rangeur/
  RangeurApp.swift       App, fenêtre, barre latérale, menu de la barre des menus
  AppState.swift         Logique : analyse du dossier, tri, annulation, réglages, notifications
  Notifier.swift         Envoi des notifications et gestion de leurs boutons
  RenameEngine.swift     Propositions de noms (Apple Intelligence + règles simples)
  FolderWatcher.swift    Surveillance du dossier en temps réel
  Models.swift           Catégories et historique
  Views/TriageView.swift La pile de cartes et les gestes de swipe
  Views/FileCard.swift   La carte d'un fichier (aperçu Quick Look)
  Views/StatsView.swift  Statistiques (Swift Charts)
  Views/ActivityView.swift, RulesView.swift, SettingsView.swift
Resources/               Info.plist et icône
build.sh                 Compile et assemble Rangeur.app
```
