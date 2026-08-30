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
- La cible application et la cible de tests compilent pour iPhoneOS avec Swift 6 et une cible minimale iOS 17.

## En cours

- Vérification réelle du parcours import → lecture → fermeture → reprise dans un simulateur iPhone 13 ou sur appareil.
- Vérification visuelle et accessibilité au format `390 × 844`.

## À faire

### Phase 1 — Fondation iPhone

- Créer l'application native iPhone. *(Implémenté ; validation sur appareil restant à faire.)*
- Mettre en place le modèle de données local pour les livres et la progression. *(Implémenté pour le premier parcours ; sessions reportées.)*
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
- Régler la police, la taille, l'interligne, le fond et le mode sombre.
- Mesurer le temps de lecture en évitant de compter une page laissée ouverte sans lecture réelle.
- Vérifier la lisibilité, les gestes, l'accessibilité et les états de chargement ou d'erreur.

### Phase 4 — Historique et statistiques essentielles

- Enregistrer les sessions de lecture.
- Afficher le temps lu aujourd'hui, cette semaine et ce mois.
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
- Le runtime iOS Simulator n’est pas disponible dans l’environnement actuel : les cibles compilent, mais les tests ne peuvent pas être exécutés et le parcours réel n’est pas encore prouvé.
- La mesure du temps de lecture exige une règle fiable pour distinguer lecture active et application simplement ouverte.
- La synchronisation iCloud peut produire des conflits si deux appareils modifient la même progression hors ligne.
- Les numéros de page ne sont pas toujours stables dans un EPUB : ils changent avec la taille du texte et la largeur de l'écran.
- L'analyse IA d'un livre complet peut être coûteuse, lente et limitée par les droits sur le contenu ; elle n'appartient pas à la première version.

## Décisions en attente

- Place future de l'IA : section principale ou outils intégrés au lecteur.
- Règle exacte d'arrêt automatique du compteur de lecture en cas d'inactivité.
- Ordre détaillé entre annotations, statistiques enrichies et synchronisation iCloud après le lecteur essentiel.

## Prochaines étapes

1. Exécuter les tests dans un environnement disposant d’un runtime iOS Simulator.
2. Tester le parcours complet sur iPhone 13 avec plusieurs EPUB légaux, dont un fichier invalide ou incomplet.
3. Vérifier visuellement le format `390 × 844`, Dynamic Type, VoiceOver et les zones tactiles.
4. Corriger les défauts observés avant de déclarer le premier parcours local terminé.
