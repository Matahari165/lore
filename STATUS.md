# État du projet Lore

Dernière mise à jour : 3 septembre 2026

## Terminé

- Vision générale définie : une application personnelle de lecture EPUB, native Apple, centrée sur la lecture, le suivi et l'exploitation personnelle des livres.
- Priorité produit fixée à l'iPhone, avec une conception de référence en `390 × 844`.
- Périmètre initial organisé autour de la bibliothèque, du lecteur, de l'historique et des statistiques.
- Le Mac reste différé ; le premier lot IA est désormais intégré au socle de lecture utilisable.
- Organisation initiale du travail et responsabilités des agents formalisées dans `AGENTS.md`.
- Périmètre de la V1 validé et consigné dans `PROJECT.md`.
- Dépôt Git initialisé sur la branche `chore/project-foundation`.
- Appareil de référence confirmé : iPhone 13, avec iOS 26 comme version minimale.
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
- La navigation comporte trois onglets synchronisés autour d’un seul état : Accueil, Bibliothèque et Statistiques.
- L’Accueil présente la reprise et les ajouts récents. La Bibliothèque permet la recherche, les filtres Tous / À lire / En cours / Terminés et le tri par ajout, titre, auteur ou progression, ascendant ou descendant.
- Le sélecteur Fichiers accepte plusieurs EPUB ; les imports sont traités séquentiellement, les succès partiels sont conservés et les erreurs sont récapitulées fichier par fichier.
- Le lecteur utilise Liquid Glass natif pour des commandes flottantes discrètes, avec réglages rapides puis page complète, réduction des animations/transparence et progression réactive.
- L’icône détaillée a été remplacée par une page pliée minimaliste formant un `L`.
- La compilation intégrée de l’application et de sa cible de tests réussit avec Xcode 26.6 et iOS Simulator 26.5.
- Le nouvel Accueil et la barre des trois onglets ont été vérifiés visuellement sur le simulateur `Lore iPhone 13`, en mode sombre.
- Un objectif quotidien global et facultatif peut être défini entre 5 et 180 minutes depuis les réglages de l’Accueil. Sa progression exacte alimente un affichage compact dans Accueil et Statistiques, avec un état explicite lorsqu’il est atteint ou lorsque les données sont indisponibles.
- Les taps gauche, centre et droit ne tournent plus les pages : ils affichent ou masquent uniquement les commandes. Le défilement, les gestes Readium et le sommaire restent disponibles.
- La sélection active utilise un texte presque noir sur fond cyan vif, distinct du surlignage jaune persistant. Le menu conserve Copier, Traduire et Définition et ajoute Surligner et Expliquer.
- Le client IA utilise l’API Responses avec le modèle exact `gpt-5.6-luna`, `store: false`, des délais bornés et une clé stockée dans le trousseau sécurisé. Aucun appel n’est effectué sans clé.
- L’explication extrait localement le passage et une fenêtre bornée avant/après dans le chapitre courant. Le résumé quotidien utilise les Locator de la veille, s’arrête au dernier passage lu et n’est présenté qu’une fois par livre et par jour local.
- Les réglages permettent d’enregistrer ou supprimer la clé sans l’afficher ni effectuer de requête de validation.
- Les surlignages sont persistés localement par livre avec le Locator Readium complet, le texte, la date et la couleur. Ils sont restaurés dans le livre, consultables depuis le lecteur, ouvrables au passage exact et supprimables avec confirmation.
- La suppression d’un livre supprime ses surlignages dans la même sauvegarde. Les échecs de suppression et les erreurs d’agrégation de l’objectif ne sont pas présentés comme des réussites ou des valeurs nulles.
- La compilation finale de l’application et de sa cible de tests réussit après revue QA indépendante. La nouvelle version IA signée est installée sur l’iPhone 13 physique ; son lancement automatisé reste à confirmer une fois l’appareil déverrouillé.
- Les réponses IA du lecteur rendent désormais le Markdown (titres, gras, italiques et listes) au lieu d’afficher ses signes bruts.
- La fermeture du lecteur est placée en haut à droite. La sélection sombre est renforcée directement dans le contenu EPUB avec un fond cyan vif et un texte presque noir.
- Les réglages permettent d’effacer, après confirmation, uniquement le temps du jour local sans supprimer la portion éventuelle d’une session appartenant à un autre jour.
- Un appui long sur un livre permet de le marquer terminé ou non terminé. Les statistiques affichent en bas les couvertures des livres terminés, filtrables par année.
- L’icône de l’application reprend uniquement le symbole `L` plié violet dans un document Icon Composer (`fill: none`, ombre `none`, asset RGBA transparent). La composition ne contient aucun aplat, halo ou image de fond ; iOS 26 conserve la possibilité d’appliquer son propre masque/arrière-plan système.
- Le produit IA est recentré sur une conversation générale avec le livre, des résumés de chapitres, des questions sur le texte lu et une analyse de fin. Les flashcards et la mémoire structurée inter-chapitres sont abandonnées.
- Toutes les couvertures utilisent désormais un cadre portrait commun : l’image entière reste visible, sans étirement, recadrage ni débordement dans Accueil, Bibliothèque et Statistiques.
- L’Accueil affiche jusqu’à quatre livres à reprendre, triés par dernière activité de lecture réelle, avec une reprise indépendante pour chacun.
- Le trait violet du logo transparent a été épaissi d’environ 80 % sans ajouter de fond, halo ni ombre.
- Le socle local de Discussion par livre est ajouté : historique multi-tours borné, stockage SwiftData local, suppression avec le livre et client IA anti-spoiler.
- L’écran Discussion est maintenant accessible depuis le lecteur, l’Accueil et la Bibliothèque. Il conserve l’historique local, affiche le contexte utilisé, rend le Markdown et propose résumé, question libre et discussion de fin.
- La barre des trois onglets se réduit au défilement vers le bas et réapparaît en remontant. Les titres Accueil, Bibliothèque et Activité sont alignés avec leurs actions afin de supprimer l’espace supérieur perdu.
- Le logo transparent a encore été agrandi et épaissi, sans fond, halo ni ombre.
- Les couvertures utilisent maintenant des rangées fixes de trois éléments avec des zones de titre, auteur et statut de hauteur identique. L’Accueil affiche jusqu’à six ajouts récents et la reprise n’affiche plus la date de dernière lecture.
- Un appui long sur une pochette ouvre les passages surlignés, l’évaluation de fin ou la discussion IA. La fin d’un livre demande une note entière sur 10 avec dix étoiles et l’année de lecture.
- Le lecteur justifie le texte, conserve en mémoire les deux dernières publications ouvertes pour accélérer les réouvertures et anime son apparition/sa fermeture en respectant Réduire les animations. Son panneau supérieur affiche la progression et son pourcentage.
- L’Accueil affiche sous Reprendre un bilan local du temps et des livres lus la veille. Un toucher sur l’objectif ouvre un graphique réel des minutes de la semaine ou du mois.
- Les statistiques affichent sous le calendrier les seules couvertures déclarées lues depuis 2026. Les réglages indiquent le modèle IA exact `gpt-5.6-luna`.
- L’icône de discussion visible sur les pochettes a été supprimée ; l’action reste disponible par appui long avec une icône d’étincelles. Le `L` de l’icône d’application est blanc, légèrement agrandi et sans arrière-plan dans l’asset fourni.
- Les titres Accueil et Bibliothèque sont désormais de vrais en-têtes dans le contenu, ce qui évite leur troncature dans la barre d’outils. Reprendre affiche deux commandes 44 × 44 identiques : ouvrir et discuter.
- L’Accueil affiche les trois derniers livres consultés. Son bloc Hier conserve la durée et les titres, puis génère un résumé IA court en puces, borné à trois livres et mis en cache pour éviter les appels répétés.
- Le graphique d’activité indique la moyenne quotidienne sur les jours écoulés de la semaine ou du mois.
- Un appui long sur un passage surligné prépare une discussion IA avec ce passage. Les dix étoiles de notation tiennent sur une seule ligne.
- Le lecteur propose des marges horizontales et verticales globales, ainsi qu’un vocabulaire local exportable avec retour au passage exact. La sélection temporaire sombre utilise un cyan clair opaque et des poignées assorties.
- Un livre peut être retiré de Reprendre sans perdre sa progression. L’ouverture ne redécode plus la couverture et utilise une animation de page qui grandit depuis le bas, avec respect de Réduire les animations.
- La section sous Hier est désormais limitée aux trois derniers livres réellement terminés. Les barres d’objectif et de lecture sont épaissies ; la progression du lecteur devient blanche en thème sombre.
- L’animation d’ouverture et de fermeture prend la position globale de la pochette touchée comme origine, puis agrandit la surface Readium jusqu’au plein écran.
- Un quatrième onglet Podcasts est ajouté : import local de MP4, lecture audio/vidéo avec `AVPlayer`, détection des doublons par SHA-256 et sauvegarde de la position en secondes pour reprendre plus tard.

## En cours

- Vérification réelle du nouveau lecteur Liquid Glass, des réglages rapides et de l’import multiple dans le simulateur puis sur l’iPhone 13.
- Vérification réelle sur l’iPhone des taps, du menu de sélection, du contraste cyan, de la création puis du retour à un surlignage, et des écrans IA sans clé.
- Raccorder l’analyse complète d’un livre terminé : l’écran Discussion utilise actuellement uniquement les extraits disponibles jusqu’au repère courant.
- Vérification accessibilité complète : Dynamic Type, VoiceOver et réduction de transparence.
- Mesure réelle sur iPhone du gain de vitesse apporté par le cache des deux derniers livres et vérification visuelle des animations et des rangées de couvertures.
- Profilage Énergie/CPU sur l’iPhone : l’audit statique soupçonne les sauvegardes SwiftData et la réécriture des checkpoints de récap lors du défilement, mais aucune mesure Instruments n’a encore été réalisée.
- Diagnostic du lanceur de tests Xcode, qui compile les tests mais ne les exécute toujours pas.
- Vérification réelle de l’import et de la reprise d’un MP4 dans l’appareil Fichiers puis sur le simulateur ; la compilation de la nouvelle tranche réussit, mais un test de lecture réel reste à faire.

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
- Vérifier sur appareil que tous les taps simples contrôlent seulement les commandes et coexistent avec la sélection et le défilement. *(Implémenté et compilé ; preuve tactile réelle restante.)*

### Phase 4 — Historique et statistiques essentielles

- Enregistrer les sessions de lecture. *(Implémenté localement.)*
- Afficher le temps lu aujourd'hui, cette semaine et ce mois. *(Agrégats implémentés ; interface reportée.)*
- Afficher les livres terminés par période avec leurs couvertures.
- Conserver les dates de début et de fin de chaque livre.
- Ajouter une note personnelle sur 10.
- Ajouter un calendrier de lecture simple.

### Phase 5 — Annotations

- Ajouter les surlignages et les notes. *(Surlignages implémentés ; notes restantes.)*
- Permettre de retrouver rapidement un passage annoté. *(Implémenté pour les surlignages avec Locator complet ; essai appareil restant.)*

### Phase 6 — Synchronisation iCloud

- Synchroniser les métadonnées de la bibliothèque, la progression, les sessions et les annotations entre appareils Apple.
- Tester séparément la synchronisation des fichiers EPUB complets avant de la déclarer prise en charge.
- Gérer les conflits et les interruptions de synchronisation sans perdre de données.
- Tester d'abord entre deux environnements iPhone avant d'étendre au Mac.

### Plus tard — Après le premier lot IA

- Application Mac complète.
- Questions-réponses approfondies sur un livre.
- Analyse complète des livres terminés et recommandations fondées sur les lectures et notes.
- Analyse et discussion de fin de livre avec l'IA.

## Problèmes et risques connus

- Le format EPUB varie selon les éditeurs ; certains fichiers peuvent être mal structurés ou protégés.
- L’application normale a déjà été vérifiée sur `Lore iPhone 13`, mais le lanceur XCTest reste bloqué sur `waiting for workers to materialize` ; un premier clone a ensuite échoué avec `Invalid device state` et `server died`. Les tests compilent, mais leur exécution automatique n’est pas encore prouvée.
- Pour cette tranche, `simctl install` n’a pas créé le conteneur de l’application après le redémarrage du simulateur ; aucune capture des nouveaux réglages ou du sommaire n’est donc disponible.
- L’automatisation tactile du simulateur ne transmet pas les clics : l’ouverture du sélecteur Fichiers n’est donc pas encore prouvée. L’import après sélection, la lecture et la reprise ont été vérifiés avec des harnais temporaires appelant les composants de production, puis entièrement supprimés.
- L’exécution des tests sur `Lore iPhone 13` reste bloquée avant le lancement du processus de tests (`waiting for workers to materialize`) ; la compilation du code et des tests réussit, mais leur exécution automatique n’est pas encore prouvée.
- La première tentative de lancement sur l’iPhone a été refusée car l’appareil était verrouillé ; une seconde tentative après déverrouillage a réussi.
- La version IA du 31 août est bien installée sur l’iPhone, mais sa tentative de lancement automatique a été refusée car l’appareil était verrouillé.
- La synchronisation iCloud peut produire des conflits si deux appareils modifient la même progression hors ligne.
- Les numéros de page ne sont pas toujours stables dans un EPUB : ils changent avec la taille du texte et la largeur de l'écran.
- L’analyse IA d’un livre complet reste hors périmètre ; seules des fenêtres bornées sont envoyées.

## Décisions en attente

- Budget mensuel maximal souhaité pour l’API OpenAI après les premiers essais réels.
- Ordre détaillé entre annotations, statistiques enrichies et synchronisation iCloud après le lecteur essentiel.

## Prochaines étapes

1. Installer la nouvelle version sur l’iPhone 13 puis vérifier les taps, la sélection cyan, les cinq actions du menu et l’état IA sans clé.
2. Définir un objectif quotidien, lire quelques minutes puis vérifier son actualisation dans Accueil et Statistiques.
3. Stabiliser le lancement du clone de test Xcode, puis exécuter les tests sur `Lore iPhone 13`.
4. Tester le parcours complet avec plusieurs EPUB légaux, dont un fichier invalide ou incomplet.
5. Vérifier Dynamic Type, VoiceOver et les zones tactiles avant de déclarer ce lot entièrement validé.
