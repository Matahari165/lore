# Lore

Lore est une application native iPhone qui transforme une bibliothèque EPUB et des fichiers audio/vidéo locaux en une boucle simple : importer, lire ou écouter, reprendre exactement, annoter et suivre son activité.

Le projet est personnel et local-first. Il sert à explorer SwiftUI, SwiftData, Readium, la persistance fiable d’un Locator de lecture et une aide IA dont le contexte est explicitement borné.

> État de référence : 17 septembre 2026. Les mentions « vérifié » ci-dessous reprennent les preuves consignées dans `STATUS.md`; elles ne remplacent pas une nouvelle exécution.

## Parcours principal

| Fonction | État actuel |
| --- | --- |
| Import d’EPUB sans DRM, copie privée et détection de doublons par SHA-256 | Implémenté ; import, métadonnées, couverture et persistance ont été vérifiés sur un EPUB réel. |
| Lecture Readium et reprise par Locator complet | Implémenté ; un parcours de lecture et de reprise après relance est documenté. |
| Bibliothèque, recherche, filtres, tri, collections, surlignages, notes et vocabulaire | Implémentés localement ; les vérifications tactiles et d’accessibilité complètes restent à faire. |
| Sessions de lecture, objectif quotidien et statistiques | Implémentés ; la cible de tests compile, mais l’exécution XCTest n’est pas encore prouvée de bout en bout. |
| Podcasts MP4, lecture audio/vidéo et reprise | Implémentés ; les parcours appareil, interruption, écran verrouillé et vérification visuelle restent partiellement ouverts. |
| Discussion IA et résumés bornés | Implémentés avec clé dans le trousseau, `store: false` et extraits locaux limités ; les tests d’interface réels restent incomplets. |
| Synchronisation iCloud / CloudKit | Non activée et non prouvée entre deux appareils. Elle reste une évolution future. |
| Version Mac | Hors périmètre de la V1. |

Captures d’écran et vidéo de démonstration : **TODO**. Aucune capture n’est incluse dans ce dépôt, donc aucune n’est inventée ici.

## Architecture

- **Interface et cycle de vie :** SwiftUI, avec une navigation iPhone en quatre onglets : Accueil, Bibliothèque, Statistiques et Podcasts.
- **Données :** SwiftData local pour les métadonnées, sessions, annotations, vocabulaire, collections et conversations ; les fichiers importés restent dans `Application Support`.
- **Lecture EPUB :** Readium Swift Toolkit 3.11. La position est conservée sous forme de Locator Readium complet et versionné, plutôt qu’avec un numéro de page instable.
- **Lecture audio/vidéo :** `AVPlayer` pour les MP4 importés localement.
- **IA :** API Responses d’OpenAI, modèle `gpt-5.6-luna`, clé stockée dans le trousseau iOS. L’application n’envoie du texte qu’après une action explicite et limite le contexte au passage ou à la progression autorisée.
- **Sauvegarde :** export local versionné séparant les données structurées des EPUB/MP4 ; restauration additive et idempotente.

Le détail du produit et des décisions se trouve dans [PROJECT.md](PROJECT.md). Le suivi interne des preuves et des risques se trouve dans [STATUS.md](STATUS.md).

## Confidentialité et limites

Les livres, positions, notes, surlignages, conversations et fichiers importés sont privés et locaux par défaut. Aucun livre, EPUB, MP4, contenu utilisateur ou clé API n’est fourni dans le dépôt.

La fonction IA est la seule sortie réseau prévue : lorsqu’elle est activée par l’utilisateur, Lore envoie à OpenAI un contexte textuel borné. Les Locators et les fichiers complets restent locaux ; `store: false` est utilisé côté API. Une clé ne doit jamais être ajoutée au code ou à Git.

CloudKit n’est pas activé dans le store SwiftData actuel (`cloudKitDatabase: .none`). Il ne faut donc pas présenter Lore comme une application synchronisée entre appareils.

## Pré-requis et lancement

- macOS avec Xcode 26.6 ;
- iOS 26 ou le simulateur iOS 26.5 ;
- un iPhone 13 peut servir d’appareil de référence ;
- une clé OpenAI est uniquement nécessaire pour les fonctions IA et doit être saisie dans l’application, jamais dans un fichier du dépôt.

Ouvrir `Lore.xcodeproj` dans Xcode, sélectionner le scheme `Lore`, puis choisir un simulateur iPhone. Pour les commandes reproductibles et leurs limites, consulter [docs/VALIDATION.md](docs/VALIDATION.md).

Build de l’application :

```sh
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
xcodebuild -project Lore.xcodeproj \
  -scheme Lore \
  -destination 'platform=iOS Simulator,name=Lore iPhone 13,OS=26.5' \
  -derivedDataPath /tmp/lore-derived-data \
  CODE_SIGNING_ALLOWED=NO build
```

Build de la cible de tests :

```sh
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
xcodebuild -project Lore.xcodeproj \
  -scheme Lore \
  -destination 'platform=iOS Simulator,name=Lore iPhone 13,OS=26.5' \
  -derivedDataPath /tmp/lore-derived-data \
  CODE_SIGNING_ALLOWED=NO build-for-testing
```

La compilation et l’exécution XCTest sont deux preuves différentes. Dans l’état documenté actuel, la cible de tests compile mais son lancement reste bloqué par l’environnement du simulateur.

## Structure du dépôt

```text
Lore/                         Code SwiftUI, données, lecteur, IA et réglages
LoreTests/                    Tests unitaires et de contrats
Lore.xcodeproj/               Projet Xcode et dépendances Swift Package Manager
PROJECT.md                    Contrat produit et décisions
STATUS.md                     Journal de validation et risques connus
docs/VALIDATION.md            Commandes et niveaux de preuve
THIRD_PARTY_NOTICES.md        Dépendances et liens officiels
```

## Licence et réutilisation

Tous droits réservés. Ce dépôt n’accorde aucun droit de copie, modification, redistribution ou réutilisation sans autorisation écrite préalable. Les dépendances tierces restent soumises à leurs propres conditions ; voir [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
