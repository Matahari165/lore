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
- Appareil principal : iPhone 13.

## V1 validée — iPhone

### Bibliothèque

- Import simultané d’un ou plusieurs fichiers EPUB sans protection DRM depuis l’app Fichiers.
- Affichage de la couverture, du titre et de l’auteur.
- Statuts : à lire, en cours et terminé.
- Trois onglets principaux : Accueil, Bibliothèque et Statistiques.
- Recherche et tri par ajout, titre, auteur ou progression, dans les deux ordres.
- Filtres de catégorie : tous, à lire, en cours et terminés.
- Conservation de la bibliothèque après fermeture de l’application.

### Lecteur

- Un tap sur le contenu affiche ou masque les commandes sans tourner la page. La navigation reste assurée par le défilement, les gestes Readium et le sommaire.
- Navigation par chapitres.
- Réglages de police, taille du texte, interligne et thème clair ou sombre.
- Reprise au passage exact.
- Progression en pourcentage et par chapitres.
- Sélection cyan très contrastée en thème sombre avec les actions Copier, Surligner, Expliquer, Traduire et Définition.
- Explication simple du passage sélectionné par l’IA avec un contexte borné dans le chapitre courant.
- Résumé de la lecture de la veille à la première ouverture pertinente de la journée, sans répétition le même jour.
- Création et suppression de surlignages persistants, consultables depuis le lecteur avec retour direct au passage.
- Création, modification et suppression de notes.
- Mesure automatique du temps de lecture actif.
- Arrêt du compteur lorsque l’application passe en arrière-plan ou après une période d’inactivité.

### Historique et statistiques

- Temps lu aujourd’hui, cette semaine et ce mois.
- Calendrier des jours de lecture.
- Objectif quotidien configurable en minutes, avec progression et confirmation lorsqu’il est atteint.
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
- Questions sur tout le livre.
- Interface générale de discussion avec le livre, incluant les résumés de chapitres et les questions sur le texte lu. *(Architecture validée ; interface à construire.)*
- Recommandations avancées.
- Interface complète de discussion et analyse de fin de livre. *(Contrat et prompt prêts.)*
- Séries de jours et statistiques complexes.

## Définition de terminé de la V1

La V1 est terminée lorsque :

- un EPUB valide peut être importé depuis l’app Fichiers ;
- sa couverture, son titre et son auteur sont affichés ;
- le livre reste disponible après redémarrage ;
- la lecture et la navigation entre chapitres fonctionnent ;
- les réglages visuels sont conservés ;
- un tap à gauche ou à droite ne tourne pas la page et sert seulement à afficher ou masquer les commandes ;
- la reprise revient au même passage ;
- la sélection reste lisible en mode sombre et expose Copier, Surligner, Expliquer, Traduire et Définition ;
- l’explication IA utilise seulement le passage et un contexte borné, et reste désactivée sans clé ;
- le résumé de la veille n’est proposé qu’une fois par livre et par jour local ;
- les surlignages peuvent être créés, retrouvés, ouverts et supprimés ;
- les notes peuvent être créées, modifiées et supprimées ;
- le temps actif est mesuré sans compter l’arrière-plan ni une longue inactivité ;
- un objectif quotidien peut être défini et son état est calculé à partir du temps actif ;
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
- **Données locales :** SwiftData conserve les métadonnées et le Locator Readium complet ; les EPUB sont copiés dans le dossier Application Support propre à l’application.
- **iCloud :** synchronise les données entre les appareils personnels.
- **Moteur EPUB :** Readium Swift Toolkit 3.11 ouvre le livre et fournit le Locator stable utilisé pour reprendre la lecture.
- **Mesure de lecture :** enregistre des sessions actives, puis calcule les statistiques à partir de ces sessions.
- **IA :** module séparé utilisant l’API Responses d’OpenAI avec `gpt-5.6-luna`, une clé conservée dans le trousseau de l’iPhone et `store: false`.

Les choix techniques détaillés doivent privilégier les outils natifs Apple, la simplicité et l’absence de serveur quand il n’apporte pas de bénéfice nécessaire.

## Contraintes

- Priorité à l’iPhone ; ne pas concevoir la V1 autour du Mac.
- Application strictement personnelle et privée.
- EPUB sans DRM uniquement dans la V1.
- Un EPUB n’a pas de nombre de pages fixe : la référence principale est le pourcentage et les chapitres lus.
- Interface lisible, accessible et optimisée pour 390 × 844.
- Version minimale : iOS 26, correspondant à l'iPhone 13 utilisé pour Lore.
- Fonctionnement utile même sans connexion, sauf fonction IA externe éventuelle.
- Aucun service payant, déploiement ou envoi de données externe sans autorisation explicite.
- Pas de complexité ou de dépendance sans bénéfice clair.

## Décisions prises

- Nom du projet : Lore.
- Produit personnel, sans comptes multiples.
- Développement iPhone en premier ; Mac reporté.
- Appareil de référence : iPhone 13 ; version minimale : iOS 26.
- Boucle principale de V1 : importer, lire, reprendre, annoter et mesurer.
- Progression fondée sur le pourcentage et les chapitres, pas sur un nombre de pages fixe.
- Synchronisation via iCloud.
- Le premier lot IA est intégré au lecteur : expliquer une sélection et résumer la lecture de la veille.
- Premier parcours local isolé d’iCloud : import atomique d’un EPUB sans DRM, bibliothèque au lancement, lecture et reprise par Locator complet.
- L’identité d’un EPUB local est le SHA-256 de ses octets ; un second import identique retourne le livre existant.
- Les imports sont sérialisés et Readium valide la copie privée en staging avant sa promotion atomique.
- Les imports interrompus sont réconciliés au lancement ; un livre dont le fichier manque n’est jamais supprimé automatiquement.
- Un dossier final orphelin est conservé pendant 7 jours puis déplacé dans une quarantaine persistante, qui n’est jamais supprimée automatiquement.
- Le format persistant du Locator est versionné et migré par un codec centralisé.
- Direction visuelle du premier parcours : blanc cassé froid, bleu encre, couvertures comme couleur principale, lecteur immersif et commandes natives sobres.
- L’écran de lancement est la bibliothèque ; l’action « Reprendre » y reste visible lorsqu’une position de lecture existe.
- Les préférences de lecture de la V1 sont globales : elles s’appliquent à tous les livres. Le lecteur utilise des valeurs par défaut sûres si elles sont absentes ou illisibles.
- Le compteur passe en inactivité après 2 minutes sans interaction de lecture. Tourner une page, faire défiler le contenu ou agir sur un passage relance l’activité ; ouvrir les réglages ou revenir simplement au premier plan ne compte pas comme lecture.
- L’objectif quotidien est global, facultatif, exprimé en minutes et borné de 5 à 180 minutes. Sa progression utilise les sessions locales exactes ; seul l’affichage est arrondi.
- Les durées sont conservées avec leur précision réelle ; seul l’affichage utilisateur est arrondi en minutes.
- Les statistiques utilisent le fuseau local de l’iPhone et une semaine commençant le lundi.
- La date de début d’un livre correspond à sa première session réelle. La date de fin est enregistrée lorsque le livre est explicitement marqué comme terminé.
- La note personnelle est un entier de 0 à 10.
- Le lecteur utilise Liquid Glass natif pour ses commandes flottantes. Les réglages essentiels sont disponibles dans un panneau rapide, puis dans une page complète.
- Aucun tap gauche ou droit ne tourne les pages ; tout tap simple sur le contenu contrôle uniquement l’affichage des commandes.
- Les surlignages sont privés et locaux. Ils conservent le Locator Readium complet, le texte sélectionné, la date et la couleur afin de revenir au passage exact.
- Le menu de sélection conserve Copier, Traduire et Définition, puis ajoute Surligner et Expliquer.
- L’IA utilise exactement `gpt-5.6-luna` via l’API Responses, avec `store: false`. La clé n’est jamais incluse dans le code et reste dans le trousseau sécurisé de l’iPhone.
- Une explication envoie uniquement le passage sélectionné et une fenêtre bornée du chapitre courant. Le résumé quotidien peut envoyer jusqu’à 18 000 caractères de la portion lue la veille.
- Le résumé quotidien porte uniquement sur le jour civil précédent, utilise les premier et dernier Locator enregistrés et n’est présenté qu’une fois par livre pendant la journée locale.
- La navigation principale comporte trois onglets : Accueil pour reprendre rapidement, Bibliothèque pour rechercher, filtrer et trier, puis Statistiques.
- Le sélecteur de fichiers accepte plusieurs EPUB. Chaque fichier est traité séparément afin qu’un échec n’annule pas les imports déjà réussis.
- L’icône de Lore conserve uniquement le trait violet minimaliste formant un `L` plié dans Icon Composer : remplissage `none`, ombre désactivée et couche PNG RGBA transparente. Le matériau Liquid Glass reste appliqué au groupe ; iOS 26 peut toutefois ajouter son masque ou son arrière-plan système aux variantes irrégulières.
- Les couvertures utilisent un cadre portrait commun et `scaledToFit` afin de rester entières, quelles que soient leurs proportions d’origine.
- Les listes principales utilisent trois colonnes de largeur identique et des zones de texte de hauteur fixe afin de conserver des rangées parfaitement alignées.
- La fin explicite d’un livre demande une note entière sur 10 et une année de lecture ; cette année détermine son classement dans l’archive annuelle.
- Les deux publications EPUB les plus récemment ouvertes restent temporairement en mémoire afin d’accélérer leur réouverture, sans modifier le fichier ni la position Readium persistée.
- L’Accueil peut proposer jusqu’à quatre lectures à reprendre, triées par dernière activité réelle.
- Les réponses IA sont présentées avec le Markdown natif pour rendre les titres, listes et emphases réellement lisibles.
- Le contexte d’explication reste dans le chapitre courant : passage sélectionné, jusqu’à environ 2 500 caractères avant et après, métadonnées du livre et du chapitre, avec une limite globale d’environ 6 000 caractères.
- La prochaine surface IA est une conversation unique avec chaque livre : amorce avant lecture, questions et résumés pendant la lecture, puis analyse après la fin. Les flashcards et la mémoire structurée des personnages entre chapitres sont exclues.
- La surface Discussion est accessible depuis le lecteur et les listes de livres. Elle conserve ses messages localement et affiche explicitement la portée du texte envoyé.
- Lorsqu’un livre est explicitement terminé, l’utilisateur autorise Lore à sélectionner et envoyer à OpenAI des extraits pertinents provenant de l’ensemble du livre pour l’analyse finale. L’EPUB complet n’est pas envoyé en un seul bloc et aucun envoi ne se déclenche automatiquement.

## Décisions nécessitant une consultation

- L’envoi volontaire d’un passage et de son contexte borné à OpenAI est autorisé lorsque la clé est configurée ; aucun texte n’est envoyé avant.
- Budget mensuel maximal éventuel pour l’IA.
- Synchronisation ou non des fichiers EPUB complets dans iCloud.
- Ajout, retrait ou changement important d’une fonction de la V1.
- Toute dépense, suppression risquée ou décision difficilement réversible.
