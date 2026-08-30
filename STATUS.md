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

## En cours

- Définition de l'architecture technique minimale de la première version iPhone.
- Décomposition du développement en phases testables et livrables.

## À faire

### Phase 1 — Fondation iPhone

- Créer l'application native iPhone.
- Mettre en place le modèle de données local pour les livres, la progression et les sessions de lecture.
- Préparer une structure simple qui pourra accueillir iCloud plus tard sans complexifier inutilement le démarrage.
- Vérifier le fonctionnement sur un écran iPhone `390 × 844`.

### Phase 2 — Bibliothèque EPUB

- Importer un fichier `.epub` depuis l'iPhone.
- Extraire et afficher le titre, l'auteur et la couverture lorsque ces informations existent.
- Afficher les livres en cours, à lire et terminés.
- Gérer les erreurs d'import et les EPUB incomplets.

### Phase 3 — Lecteur essentiel

- Ouvrir et parcourir un EPUB.
- Reprendre exactement à la dernière position enregistrée.
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
- La mesure du temps de lecture exige une règle fiable pour distinguer lecture active et application simplement ouverte.
- La synchronisation iCloud peut produire des conflits si deux appareils modifient la même progression hors ligne.
- Les numéros de page ne sont pas toujours stables dans un EPUB : ils changent avec la taille du texte et la largeur de l'écran.
- L'analyse IA d'un livre complet peut être coûteuse, lente et limitée par les droits sur le contenu ; elle n'appartient pas à la première version.
- La direction UI détaillée n'est pas encore validée. Elle nécessitera une recherche de références, une proposition visuelle puis une validation avant implémentation importante.

## Décisions en attente

- Direction visuelle précise : ambiance neutre de type Apple ou sensation plus chaleureuse de papier.
- Écran présenté au lancement : reprise immédiate du livre en cours ou vue générale de la bibliothèque.
- Place future de l'IA : section principale ou outils intégrés au lecteur.
- Règle exacte d'arrêt automatique du compteur de lecture en cas d'inactivité.
- Ordre détaillé entre annotations, statistiques enrichies et synchronisation iCloud après le lecteur essentiel.

## Prochaines étapes

1. Faire valider l'architecture minimale de la première version par les spécialistes iOS et données.
2. Rechercher des références UI adaptées à la lecture personnelle sur iPhone, puis proposer une direction sans la figer prématurément.
3. Construire un premier parcours vertical : importer un EPUB, l'ouvrir, lire, fermer puis reprendre au bon endroit.
4. Tester ce parcours sur le format prioritaire `390 × 844` avant d'ajouter les fonctions secondaires.
