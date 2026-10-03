# Import de bibliothèque : états de lecture, notes et dates

Ce document s'adresse aux contributeurs qui touchent à l'import de fichiers
(CSV, TXT, XLSX). Il explique ce que l'import lit, pourquoi, et comment
ajouter un nouveau format d'export.

## Pourquoi cette modification

Jusqu'ici, l'import ne lisait que la fiche du livre : titre, auteur, ISBN,
éditeur, année. Tout ce que le fichier disait de la *lecture* était perdu.
Une bibliothèque Babelio de 448 livres, dont 397 marqués « Lu », arrivait
avec 448 livres « à lire » et sans aucune note.

L'import lit désormais aussi :

| Information        | Exemple de colonne                         | Stockée dans          |
|--------------------|--------------------------------------------|-----------------------|
| État de lecture    | `Statut` (Babelio), `Exclusive Shelf` (Goodreads) | `reading_status` |
| Note personnelle   | `Note` (Babelio), `My Rating` (Goodreads)  | `user_rating` (sur 10) |
| Début de lecture   | `Date Started`, `Date de début`            | `started_reading_at`  |
| Fin de lecture     | `Date Read`, `Date de lecture`, `Lu le`    | `finished_reading_at` |

Le module ne vise pas un format en particulier : n'importe quel tableur dont
les colonnes portent un nom reconnaissable en bénéficie. Les formats connus
(Babelio, Goodreads) ne précisent que ce qui ne peut pas se deviner.

## Où est le code

| Fichier | Rôle |
|---------|------|
| [`lib/utils/import_sources.dart`](../../lib/utils/import_sources.dart) | Les formats connus (`ImportSource`), la lecture des valeurs (statuts, notes, dates, ordre des noms) et le décodage du fichier. |
| [`lib/utils/import_columns.dart`](../../lib/utils/import_columns.dart) | Retrouver une colonne d'après son nom d'en-tête : auteur, ISBN, et maintenant statut, note, dates. |
| [`lib/services/api_service.dart`](../../lib/services/api_service.dart) | `importBooks` : lit le fichier, détecte le format, construit chaque `FrbBook`. Chemins CSV et XLSX. |
| `bibliogenius/src/services/book_service.rs` (dépôt Rust) | `create_book` enregistre désormais la note reçue. Sans ce correctif, la note était perdue sur un appareil sans lecteur de foyer. |

## Comment ça se déroule

1. **Décodage** (`decodeImportText`) : UTF-8 d'abord, avec ou sans BOM ;
   sinon Windows-1252. Babelio et Excel sous Windows écrivent en
   Windows-1252, et la lecture en UTF-8 échouait au premier « é ».
2. **Détection du format** (`ImportSource.detect`) à partir de la ligne
   d'en-tête : Babelio, Goodreads, ou générique.
3. **Résolution des colonnes** (`ReadingColumns.resolve`), une fois pour tout
   le fichier. Si le format ne précise pas l'échelle de notation, elle est
   déduite de la colonne : sur 5, sauf si une valeur dépasse 5.
4. **Lecture de chaque ligne** (`ReadingColumns.read`) : statut, note et
   dates, chacun facultatif. Une valeur inconnue ne donne rien plutôt qu'une
   supposition : le livre garde alors l'état par défaut.

### Règles de lecture des valeurs

- **Statuts** : le vocabulaire français et anglais est ramené aux états de
  l'app, sans tenir compte de la casse, des accents et de la ponctuation
  (« À lire », « a-lire », « to-read » donnent tous `to_read`).
  « Pense-bête » ou « wishlist » donnent `wanting`, et le livre est alors
  marqué comme **non possédé**.
- **Notes** : l'app stocke une note sur 10. Une note sur 5 est doublée, demi-
  étoiles comprises (4,5 donne 9). **0 signifie « pas de note »** chez Babelio
  comme chez Goodreads : il n'est jamais importé comme la pire note. Une
  cellule qui précise son échelle (`7/10`) l'emporte sur celle de la colonne.
- **Dates** : `2024-06-09`, `2024/06/09`, avec ou sans heure, et `09/06/2024`
  (jour d'abord). `0000-00-00` et les dates impossibles sont ignorées.
- **Date de fin sans statut** : un livre qui a une date de fin de lecture est
  considéré comme lu, même si son étagère dit « à lire ».

## Le cas Babelio

L'export « Biblio_export » de Babelio a ses particularités, toutes gérées par
le profil `ImportSource.babelio` :

```
"ISBN";"Titre";"Auteur";"Editeur";"Date de publication";"Date d`entrée dans Babelio";"Statut";"Note"
"9782359251012";"La démocratie aux champs";"Zask Joëlle";"Les Empêcheurs de penser en rond";"2016-02-11";"2026-09-05 13:42:22";"Lu";"0.0"
```

- **Encodage Windows-1252**, séparateur `;`, fins de ligne CRLF.
- **Auteur au format « Nom Prénom »**. Il est remis dans l'ordre
  « Prénom Nom », sinon la bibliothèque contiendrait chaque écrivain deux
  fois : une fois venant de Babelio, une fois venant de toutes les autres
  sources. Règles appliquées (`givenNameFirst`) :
  - le premier mot est le nom de famille (`Oates Joyce Carol` donne Joyce
    Carol Oates) ;
  - une particule en tête garde le mot suivant dans le nom (`Le Carré John`,
    `Da Costa Mélissa`) ;
  - une particule rejetée en fin de cellule revient devant le nom
    (`Bruycker Daniel de` donne Daniel de Bruycker) ;
  - un nom d'un seul mot reste tel quel (`Molière`).
- **Note de 0 à 5**, `0.0` quand le lecteur n'a pas noté.
- **La « Date d'entrée dans Babelio » n'est pas une date de lecture** et n'est
  volontairement pas importée : sur l'export de référence, 302 livres sur 448
  partagent le jour où le lecteur a transféré sa bibliothèque dans Babelio.
- **« Date de publication »** est une date complète, dont on ne garde que
  l'année.
- Certaines cellules ISBN contiennent un identifiant interne Babelio
  (`SIE89210_5239`) ou un ASIN Amazon (`978B00M5MRLY4`) : elles sont rejetées
  comme ISBN et comptées dans le rapport d'import, le livre est importé sans
  ISBN.

## Ajouter un nouveau format

Dans la plupart des cas, il n'y a **rien à faire** : si les colonnes portent
des noms courants, la lecture générique les trouve. Sinon :

1. **Un nom de colonne n'est pas reconnu** : ajouter le nom (en minuscules)
   à la liste concernée dans `import_columns.dart` (`findReadingStatusColumn`,
   `findRatingColumn`, `findFinishedDateColumn`, `findStartedDateColumn`).
   Ne mettre que des noms exacts : un mot trop courant (« date ») attraperait
   la mauvaise colonne.
2. **Une valeur de statut n'est pas reconnue** : l'ajouter à `_statusWords`
   dans `import_sources.dart`, sous sa forme « repliée » (minuscules, sans
   accents, ponctuation remplacée par des espaces).
3. **Le format a une particularité qui ne se devine pas** (ordre des noms,
   échelle de notation, colonne de date trompeuse) : déclarer un
   `ImportSource` et l'ajouter à `ImportSource.detect`, en le reconnaissant par
   une colonne qui lui est propre.
4. **Ajouter un test** dans `test/utils/import_sources_test.dart` pour les
   valeurs, et dans `test/services/api_service_import_books_test.dart` pour un
   petit fichier complet au format de la source.

N'ajoutez jamais un vrai export personnel au dépôt : reproduisez sa forme en
quelques lignes inventées, comme le font les tests existants.

## Limites connues

- **Noms de famille composés sans particule** : `Vargas Llosa Mario` a la même
  forme que `Burke James Lee`. Le premier mot étant pris pour le nom, on
  obtient « Llosa Mario Vargas ». Sur l'export de référence, 4 auteurs sur
  268 sont concernés ; ils se corrigent à la main dans la fiche du livre.
- **Pas de dédoublonnage** : réimporter un fichier crée les livres une
  seconde fois. Pour mettre à jour les lectures de livres déjà présents,
  c'est la fusion « Importer mes lectures » (foyer) qui convient, pas l'import
  de fichier.
- **Gleeph (XLSX)** : ses colonnes `wish` / `reading` / `read` restent la
  source du statut ; la colonne de statut générique n'est lue qu'en leur
  absence.
- **Mode serveur HTTP** : le parseur Rust de `modules/import` n'est pas
  concerné par cette modification et attend encore une colonne `EAN` que le
  vrai export Babelio n'a pas.

## Tests

```sh
flutter test test/utils/import_sources_test.dart \
             test/services/api_service_import_books_test.dart
# côté Rust
cargo test --lib create_book_keeps_the_reading
```
