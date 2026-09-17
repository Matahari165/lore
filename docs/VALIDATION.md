# Validation de Lore

Ce document sépare les niveaux de preuve. Une compilation réussie ne prouve pas un parcours utilisateur réel, et un test exécuté sur un simulateur ne prouve pas le comportement sur iPhone.

## Pré-requis

- Xcode 26.6 ;
- iOS Simulator 26.5 ;
- scheme `Lore` ;
- destination utilisée dans les exemples : `Lore iPhone 13` ;
- `DEVELOPER_DIR` peut pointer vers un autre Xcode complet ; les exemples utilisent `/Applications/Xcode.app` par défaut ;
- les commandes écrivent leurs artefacts dans `/tmp/lore-derived-data` afin de ne pas polluer le dépôt.

## Build reproductible

Depuis la racine du dépôt :

```sh
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
xcodebuild -project Lore.xcodeproj \
  -scheme Lore \
  -destination 'platform=iOS Simulator,name=Lore iPhone 13,OS=26.5' \
  -derivedDataPath /tmp/lore-derived-data \
  CODE_SIGNING_ALLOWED=NO build-for-testing
```

Cette commande compile l’application et la cible `LoreTests` sans demander de signature. Elle ne lance aucun test.

## Tests Swift Testing

Pour demander la compilation puis l’exécution des tests :

```sh
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
xcodebuild -project Lore.xcodeproj \
  -scheme Lore \
  -destination 'platform=iOS Simulator,name=Lore iPhone 13,OS=26.5' \
  -derivedDataPath /tmp/lore-derived-data \
  CODE_SIGNING_ALLOWED=NO test
```

État connu : `STATUS.md` rapporte que les tests compilent, mais que XCTest peut rester bloqué avant le premier résultat (`waiting for workers to materialize`, `CoreSimulatorService` indisponible ou état de simulateur invalide). Une absence de résultat n’est donc pas à présenter comme « tous les tests verts ».

## Simulateur

Preuves déjà consignées :

- lancement de Lore et vérification visuelle de l’état vide de la bibliothèque ;
- import d’un EPUB réel (*Deep Work*), affichage de la couverture, du titre et de l’auteur ;
- lecture Readium, sauvegarde d’un Locator, puis reprise au même passage après relance ;
- compilation de l’application et de la cible de tests avec Xcode 26.6 et iOS Simulator 26.5.

À refaire avant de déclarer la V1 entièrement validée : import multiple, nouveau lecteur Liquid Glass, sélection et actions d’annotation, collections, fiches détaillées, Dynamic Type, VoiceOver, réduction de transparence et états d’erreur.

## Appareil réel

Une version a été installée et lancée sur un iPhone 13. Les vérifications restantes incluent notamment :

- parcours tactile complet du lecteur et des citations ;
- lecture podcast réelle, piste audio, interruption, arrière-plan et écran verrouillé ;
- vérification visuelle à `390 × 844` ;
- VoiceOver et Dynamic Type ;
- absence de clé IA et envoi volontaire d’un contexte borné ;
- synchronisation entre deux appareils — non disponible actuellement, car CloudKit n’est pas activé.

Ces points doivent être marqués comme non prouvés tant qu’une observation appareil datée et reproductible n’est pas ajoutée.

## Ce que ce document ne prouve pas

- `build-for-testing` ne prouve pas l’exécution des tests ;
- une installation ou une ouverture de l’application ne prouve pas tous les parcours ;
- une interface locale ne prouve pas la synchronisation iCloud ;
- la présence du module IA ne prouve pas qu’une clé est configurée ni qu’un appel réseau a réussi ;
- aucune donnée personnelle de lecture n’est nécessaire pour reproduire la compilation.
