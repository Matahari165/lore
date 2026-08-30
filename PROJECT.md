# PROJECT.md — Lore

## Vision

Lore est une application personnelle de lecture, native sur iPhone puis sur Mac. Elle réunit une bibliothèque EPUB, un lecteur confortable, un historique de lecture, des statistiques fiables et une aide par intelligence artificielle.

La priorité actuelle est l’iPhone. Le Mac viendra dans une version ultérieure.

## Objectif

Permettre une boucle de lecture complète et simple :

**Importer un EPUB → lire → reprendre exactement → annoter → suivre son activité.**

## Utilisateur

- Un seul utilisateur : le propriétaire de l’application.
- Usage privé, sans fonctions sociales ni gestion de comptes multiples.
- Appareils Apple connectés au même compte iCloud.

## V1 validée — iPhone

### Bibliothèque

- Import de fichiers EPUB sans protection DRM depuis l’app Fichiers.
- Affichage de la couverture, du titre et de l’auteur.
- Statuts : à lire, en cours et terminé.
- Conservation de la bibliothèque après fermeture de l’application.

### Lecteur

- Navigation par chapitres.
- Réglages de police, taille du texte, interligne et thème clair ou sombre.
- Reprise au passage exact.
- Progression en pourcentage et par chapitres.
- Création, modification et suppression de surlignages et de notes.
- Mesure automatique du temps de lecture actif.
- Arrêt du compteur lorsque l’application passe en arrière-plan ou après une période d’inactivité.

### Historique et statistiques

- Temps lu aujourd’hui, cette semaine et ce mois.
- Calendrier des jours de lecture.
- Historique visuel avec les couvertures.
- Dates de début et de fin d’un livre.
- Note personnelle sur 10.
- Listes des livres en cours et terminés.

### Synchronisation iCloud

- Synchronisation de la progression, des notes, des surlignages, du temps de lecture, des métadonnées et du statut.
- La synchronisation des fichiers EPUB eux-mêmes doit être confirmée par un test réel sur deux appareils.

## Hors V1

- Application Mac.
- PDF et autres formats.
- EPUB protégés par DRM, notamment les livres Apple Books protégés.
- Boutique de livres.
- Comptes multiples et fonctions sociales.
- Explication d'un passage par l'intelligence artificielle.
- Questions sur tout le livre.
- Résumés automatiques de chapitres.
- Rappel automatique de la session précédente.
- Fiches de personnages et de concepts.
- Flashcards.
- Recommandations avancées.
- Discussion et analyse globale de fin de livre.
- Objectifs, séries de jours et statistiques complexes.

## Définition de terminé de la V1

La V1 est terminée lorsque :

- un EPUB valide peut être importé depuis l’app Fichiers ;
- sa couverture, son titre et son auteur sont affichés ;
- le livre reste disponible après redémarrage ;
- la lecture et la navigation entre chapitres fonctionnent ;
- les réglages visuels sont conservés ;
- la reprise revient au même passage ;
- les surlignages et notes peuvent être créés, modifiés et supprimés ;
- le temps actif est mesuré sans compter l’arrière-plan ni une longue inactivité ;
- les statistiques journalières et hebdomadaires correspondent aux sessions enregistrées ;
- les statistiques mensuelles, le calendrier de lecture et l'historique avec couvertures correspondent aux sessions enregistrées ;
- les dates de début et de fin d'un livre sont conservées correctement ;
- un livre peut être noté sur 10 et marqué comme terminé ;
- les données prévues se synchronisent entre deux appareils de test utilisant le même compte iCloud ;
- les écrans principaux sont vérifiés au format iPhone 390 × 844 ;
- les états de chargement, d’absence de données et d’erreur sont traités ;
- les tests adaptés passent sans problème bloquant ;
- les documents de référence sont à jour et Git est propre.

## Architecture générale

- **Application :** SwiftUI, le système natif d’Apple pour construire l’interface iPhone puis Mac.
- **Données locales :** bibliothèque, progression, annotations, sessions et statistiques restent disponibles sur l’appareil.
- **iCloud :** synchronise les données entre les appareils personnels.
- **Moteur EPUB :** ouvre le livre, affiche ses chapitres et conserve un repère stable pour reprendre la lecture.
- **Mesure de lecture :** enregistre des sessions actives, puis calcule les statistiques à partir de ces sessions.
- **IA :** module séparé afin de pouvoir choisir plus tard une solution locale ou externe sans reconstruire le lecteur.

Les choix techniques détaillés doivent privilégier les outils natifs Apple, la simplicité et l’absence de serveur quand il n’apporte pas de bénéfice nécessaire.

## Contraintes

- Priorité à l’iPhone ; ne pas concevoir la V1 autour du Mac.
- Application strictement personnelle et privée.
- EPUB sans DRM uniquement dans la V1.
- Un EPUB n’a pas de nombre de pages fixe : la référence principale est le pourcentage et les chapitres lus.
- Interface lisible, accessible et optimisée pour 390 × 844.
- Fonctionnement utile même sans connexion, sauf fonction IA externe éventuelle.
- Aucun service payant, déploiement ou envoi de données externe sans autorisation explicite.
- Pas de complexité ou de dépendance sans bénéfice clair.

## Décisions prises

- Nom du projet : Lore.
- Produit personnel, sans comptes multiples.
- Développement iPhone en premier ; Mac reporté.
- Boucle principale de V1 : importer, lire, reprendre, annoter et mesurer.
- Progression fondée sur le pourcentage et les chapitres, pas sur un nombre de pages fixe.
- Synchronisation via iCloud.
- Toutes les fonctions IA sont reportées après le premier socle utilisable.

## Décisions nécessitant une consultation

- Autoriser ou non l’envoi de passages à un service d’IA externe.
- Budget mensuel maximal éventuel pour l’IA.
- Direction visuelle et organisation des écrans principaux.
- Durée exacte avant arrêt pour inactivité ; point de départ recommandé : 2 minutes.
- Synchronisation ou non des fichiers EPUB complets dans iCloud.
- Version minimale d’iOS si elle exclut un appareil personnel.
- Ajout, retrait ou changement important d’une fonction de la V1.
- Toute dépense, suppression risquée ou décision difficilement réversible.
