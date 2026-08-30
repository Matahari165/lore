# État du projet Lore

Dernière mise à jour : 30 août 2026

## Terminé

- Vision générale définie : une application personnelle de lecture EPUB, native Apple, centrée sur la lecture, le suivi et l'exploitation personnelle des livres.
- Priorité produit fixée à l'iPhone, avec une conception de référence en `390 × 844`.
- Périmètre initial organisé autour de la bibliothèque, du lecteur, de l'historique et des statistiques.
- Le Mac et toutes les fonctions d'IA sont explicitement différés jusqu'à l'obtention d'un premier socle de lecture utilisable.
- Organisation initiale du travail et responsabilités des agents formalisées dans `AGENTS.md`.
- Périmètre de la V1 validé et consigné dans `PROJECT.md`.
- Dépôt Git initialisé sur la branche `chore/project-foundation`.
- Appareil de référence confirmé : iPhone 13, avec iOS 17 comme version minimale.
- Quatre conversations spécialisées actives et isolées : iOS, EPUB/données/iCloud, UI/UX et QA.
- Architecture locale du premier parcours arrêtée : SwiftUI, SwiftData, fichiers privés dans Application Support et Readium Swift Toolkit 3.11.
- Projet Xcode iPhone créé et première implémentation locale ajoutée : import depuis Fichiers, copie atomique, métadonnées et couverture, bibliothèque, lecteur et sauvegarde du Locator complet.
- Direction du premier parcours appliquée : bibliothèque au lancement, « Reprendre » visible, blanc cassé froid, bleu encre, couvertures dominantes et lecteur immersif.
- Le runtime iOS 26.5 est installé et un appareil virtuel `Lore iPhone 13` est disponible. La compilation complète de l’application réussit sur ce simulateur.
- Lore est installé et lancé réellement sur `Lore iPhone 13` ; l’état vide de la bibliothèque est vérifié visuellement au format de référence.
- Le libellé du bouton principal d’import, initialement invisible, a été corrigé et confirmé par une seconde capture du simulateur.
- L’EPUB réel *Deep Work* a été validé puis importé par le pipeline de production : couverture, titre `Deep Work`, auteur `Cal Newport`, copie privée et persistance après relance sont confirmés.
- Le lecteur Readium rend réellement le livre. Après huit avances de page, le Locator `Introduction`, position `8`, progression `37,5 %` a été sauvegardé puis restauré au même passage après relance.
- L’import local est durci : SHA-256, retour du doublon, file unique, staging privé validé par Readium puis promotion atomique.
- Une réconciliation prudente traite les imports interrompus, nettoie seulement les staging non référencés de plus de 24 heures, conserve les livres au fichier manquant et déplace les dossiers finaux orphelins de plus de 7 jours dans une quarantaine persistante jamais supprimée automatiquement.
- Un doublon dont le fichier final est absent ou invalide est réparé depuis la nouvelle copie staging validée, sans remplacer son identité ni sa progression.
- La persistance du Locator est versionnée ; un échec de sauvegarde conserve la position en attente, empêche la fermeture normale du lecteur et est retenté au retour actif.
- Des tests couvrant les contrats critiques d’import, de réconciliation et de cycle de vie du lecteur ont été ajoutés et compilent. Leur première exécution a été bloquée par la préparation initiale du simulateur, sans échec de test observé.
- Le socle local des sessions de lecture est implémenté avec SwiftData : démarrage à la première interaction de lecture réelle, arrêt en arrière-plan ou à la fermeture, seuil d’inactivité isolé à 2 minutes et récupération prudente après interruption.
- Les durées exactes et les agrégats aujourd’hui, semaine commençant le lundi et mois sont exposés à l’interface, selon le calendrier et le fuseau locaux de l’iPhone. Aucune interface de statistiques ni synchronisation iCloud n’est incluse dans ce jalon.
- Le timer utilise une horloge injectable et une durée monotone pour résister aux changements de l’heure système. Des tests déterministes couvrent l’inactivité, les interactions tardives, le retour au premier plan, les erreurs d’arrêt, la reprise après interruption et les frontières jour/semaine/mois.
- Les préférences globales du lecteur (taille, sérif/sans sérif, interligne et thème clair/sombre) sont conservées dans `UserDefaults` et soumises à Readium à l’ouverture comme pendant la lecture.
- Le lecteur expose un sommaire hiérarchique issu du manifeste EPUB et navigue avec les `Link` Readium, sans remplacer le Locator de reprise par un numéro de page.
- Les commandes du lecteur utilisent les événements de toucher Readium et des barres limitées au haut et au bas de l’écran afin de préserver la sélection native et les gestes de pagination.
- Les tests de préférences, bornes, traduction Readium, sommaire et navigation ont été ajoutés et leur cible compile ; leur exécution reste bloquée par le lanceur XCTest du simulateur.
- Le contrat de données de l’écran Statistiques est raccordé aux vraies sessions et aux livres : totaux exacts, jours de lecture du mois, historique en cours/terminé avec couverture, première session réelle, fin explicite et note entière 0–10. L’interface reste dans son lot séparé.

## En cours

- Vérification réelle du parcours import → lecture → fermeture → reprise dans un simulateur iPhone 13 ou sur appareil.
- Vérification visuelle et accessibilité au format `390 × 844`.
- Développement parallèle de la prochaine tranche : réglages et sommaire du lecteur par IOS / ARCHITECTURE APPLE.
- Développement parallèle du timer actif, des sessions et des agrégations locales par EPUB / DONNÉES / ICLOUD.
- Conception et implémentation du premier écran Historique & statistiques par UI / UX LECTURE.
- Diagnostic du clone de tests Xcode et préparation de la matrice de régression par QA / REVIEW.

## À faire

### Phase 1 — Fondation iPhone

- Créer l'application native iPhone. *(Implémenté ; validation sur appareil restant à faire.)*
- Mettre en place le modèle de données local pour les livres, la progression et les sessions. *(Implémenté pour le premier parcours local.)*
- Préparer une structure simple qui pourra accueillir iCloud plus tard sans complexifier inutilement le démarrage.
- Vérifier le fonctionnement sur un écran iPhone `390 × 844`.

### Phase 2 — Bibliothèque EPUB

- Importer un fichier `.epub` depuis l'iPhone. *(Implémenté ; essai système restant.)*
- Extraire et afficher le titre, l'auteur et la couverture lorsque ces informations existent. *(Implémenté ; essai avec plusieurs EPUB restant.)*
- Afficher les livres en cours, à lire et terminés.
- Gérer les erreurs d'import et les EPUB incomplets.

### Phase 3 — Lecteur essentiel

- Ouvrir et parcourir un EPUB. *(Implémenté avec Readium ; essai système restant.)*
- Reprendre exactement à la dernière position enregistrée. *(Implémenté avec le Locator complet ; preuve après relance restant à obtenir.)*
- Régler la police, la taille, l'interligne, le fond et le mode sombre. *(Implémenté pour taille, sérif/sans sérif, interligne et thèmes clair/sombre ; vérification visuelle réelle restant à faire.)*
- Mesurer le temps de lecture en évitant de compter une page laissée ouverte sans lecture réelle. *(Socle local implémenté ; validation réelle du timer restant à faire.)*
- Vérifier la lisibilité, les gestes, l'accessibilité et les états de chargement ou d'erreur.

### Phase 4 — Historique et statistiques essentielles

- Enregistrer les sessions de lecture. *(Implémenté localement.)*
- Afficher le temps lu aujourd'hui, cette semaine et ce mois. *(Agrégats implémentés ; interface reportée.)*
- Afficher les livres terminés par période avec leurs couvertures.
- Conserver les dates de début et de fin de chaque livre.
- Ajouter une note personnelle sur 10.
- Ajouter un calendrier de lecture simple.

### Phase 5 — Annotations

- Ajouter les surlignages et les notes.
- Permettre de retrouver rapidement un passage annoté.

### Phase 6 — Synchronisation iCloud

- Synchroniser les métadonnées de la bibliothèque, la progression, les sessions et les annotations entre appareils Apple.
- Tester séparément la synchronisation des fichiers EPUB complets avant de la déclarer prise en charge.
- Gérer les conflits et les interruptions de synchronisation sans perdre de données.
- Tester d'abord entre deux environnements iPhone avant d'étendre au Mac.

### Plus tard — Hors première version

- Application Mac complète.
- Questions-réponses approfondies sur un livre.
- Résumés de chapitres, personnages, concepts, flashcards et recommandations.
- Rappel intelligent du contexte au début d'une session.
- Analyse et discussion de fin de livre avec l'IA.

## Problèmes et risques connus

- Le format EPUB varie selon les éditeurs ; certains fichiers peuvent être mal structurés ou protégés.
- L’application normale a déjà été vérifiée sur `Lore iPhone 13`, mais le lanceur XCTest reste bloqué sur `waiting for workers to materialize` ; un premier clone a ensuite échoué avec `Invalid device state` et `server died`. Les tests compilent, mais leur exécution automatique n’est pas encore prouvée.
- Pour cette tranche, `simctl install` n’a pas créé le conteneur de l’application après le redémarrage du simulateur ; aucune capture des nouveaux réglages ou du sommaire n’est donc disponible.
- L’automatisation tactile du simulateur ne transmet pas les clics : l’ouverture du sélecteur Fichiers n’est donc pas encore prouvée. L’import après sélection, la lecture et la reprise ont été vérifiés avec des harnais temporaires appelant les composants de production, puis entièrement supprimés.
- L’exécution des tests sur `Lore iPhone 13` reste bloquée avant le lancement du processus de tests (`waiting for workers to materialize`) ; la compilation du code et des tests réussit, mais leur exécution automatique n’est pas encore prouvée.
- La synchronisation iCloud peut produire des conflits si deux appareils modifient la même progression hors ligne.
- Les numéros de page ne sont pas toujours stables dans un EPUB : ils changent avec la taille du texte et la largeur de l'écran.
- L'analyse IA d'un livre complet peut être coûteuse, lente et limitée par les droits sur le contenu ; elle n'appartient pas à la première version.

## Décisions en attente

- Place future de l'IA : section principale ou outils intégrés au lecteur.
- Ordre détaillé entre annotations, statistiques enrichies et synchronisation iCloud après le lecteur essentiel.

## Prochaines étapes

1. Stabiliser le lancement du clone de test Xcode, puis exécuter les tests sur `Lore iPhone 13`.
2. Tester le parcours complet sur iPhone 13 avec plusieurs EPUB légaux, dont un fichier invalide ou incomplet.
3. Vérifier visuellement le format `390 × 844`, Dynamic Type, VoiceOver et les zones tactiles.
4. Corriger les défauts observés avant de déclarer le premier parcours local terminé.
