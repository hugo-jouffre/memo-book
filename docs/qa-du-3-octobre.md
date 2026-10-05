# QA du 3 octobre 2026 — ce qui attend une décision

La session de QA qui a suivi le crédit du jour et l'abonnement mensuel (PR #84
à #93) a corrigé seule tout ce qui ne demandait pas d'arbitrage : la liste est
dans la PR `qa-du-3-octobre`. Restent ici **les seize questions** qu'elle ne
pouvait pas trancher.

**Pour répondre** : un mot en face de « Réponse » suffit — la lettre d'une
option, « reco », ou une phrase. Une recommandation est donnée à chaque fois ;
« reco » veut dire qu'on l'applique telle quelle. Les textes cités sont ceux
de l'app, au caractère près. Quand une réponse change un texte, Figma est à
mettre à jour d'abord (R3, R8).

Les numéros `T…` renvoient aux tickets ouverts de
[`ui-development.md`](ui-development.md).

---

## Paywall et abonnement

### D1 — Les mentions qu'Apple attend sous l'offre

Apple (règle 3.1.2) veut voir **sur le paywall même** le nom de l'abonnement,
sa durée et son prix, et l'usage veut aussi le prélèvement par le compte
Apple et la résiliation 24 h avant la fin de la période. Aujourd'hui le pied
dit seulement « Renouvellement automatique pour 4,99 €/mois » et « résiliable
à tout moment, rappel à la fin du voyage » ; le nom de l'offre n'apparaît pas
(« Passe en illimité » n'est qu'un surtitre), et le reste n'est que dans les
CGU, à deux touches. C'est un motif de rejet fréquent à la revue.

- **a.** Ajouter sous le pied une ligne en petit : « MemoBook Illimité,
  4,99 € par mois. Payé par ton compte Apple, renouvelé chaque mois sauf
  résiliation au moins 24 h avant la fin de la période, dans Réglages ›
  ton nom › Abonnements. »
- **b.** Garder le pied tel quel et compter sur les CGU.

**Reco : a**, à dessiner dans Figma avec T251 (le voile du pied, qui estompe
déjà les liens légaux).

Réponse :

### D2 — « Ton carnet est imprimé et livré chez toi »

Sur l'écran d'offre, la carte « Vite fait, bien fait ! Ton carnet est imprimé
et livré chez toi quelques jours après ton retour ! » est posée entre les deux
avantages de l'abonnement. On comprend que l'impression est comprise ; la
FAQ, les CGU et le README disent qu'elle se paie à part.

- **a.** La retirer de l'offre.
- **b.** La reformuler : « Quand tu veux, ton carnet s'imprime et arrive chez
  toi — il se commande à part. »
- **c.** La garder telle quelle.

**Reco : b.**

Réponse :

### D3 — « Aussi longtemps que ton voyage dure »

Deux phrases du paywall datent de l'abonnement « le temps du voyage » :
« Illimité : raconte autant que tu veux, aussi longtemps que ton voyage dure. »
et « Raconte autant que tu veux : tout est mis en page automatiquement, tout
au long de ton voyage ». L'abonnement est maintenant mensuel, personnel, et
vaut pour tous les voyages.

- **a.** « … sur tous tes voyages. » à la place de la fin de ces deux phrases.
- **b.** Garder.

**Reco : a** (à rattacher à T247, les textes du nouveau modèle).

Réponse :

### D4 — « Le rappel à la fin de chaque voyage »

Le paywall, la FAQ, les CGU et la politique de confidentialité promettent un
rappel de résiliation « à la fin du voyage » ou « de chaque voyage ». En vrai,
il ne part que si l'abonnement va se renouveler **et** qu'aucun autre voyage
ne court ni ne s'annonce (`notifications.md`) — sinon on pousserait à résilier
quelqu'un qui raconte encore.

- **a.** Dire vrai partout : « quand ton dernier voyage en cours se termine ».
- **b.** Envoyer le rappel à la fin de chaque voyage, même s'il en reste un.

**Reco : a.** Les CGU et la confidentialité sont aussi à republier sur
memobook.fr.

Réponse :

### D5 — Le remboursement, dans la FAQ

Les CGU disent « aucun remboursement au prorata, les demandes passent par
Apple ». La FAQ n'en parle pas, et sa recherche ne trouve rien au mot
« remboursement ».

- **a.** Ajouter à « Comment marche l'abonnement ? » : « Un mois commencé est
  dû ; pour un remboursement, c'est Apple qui décide, depuis
  reportaproblem.apple.com. »
- **b.** Ne rien ajouter.

**Reco : a.**

Réponse :

### D6 — La politique de confidentialité promet un carnet gratuit

Le § 2.1 (formulaire bêta-testeur) promet « votre premier carnet gratuit » et
parle de « phase bêta ». Et Stripe, qui encaisse les carnets et la cagnotte,
n'est pas dans la liste des destinataires. (Voisin de T203, qui réécrit tout
le chapitre 2.)

- **a.** Retirer le § 2.1 et ajouter Stripe aux destinataires.
- **b.** Garder le § 2.1 (le formulaire du site existe encore) en retirant
  « premier carnet gratuit », et ajouter Stripe.

**Reco : b** si le formulaire WhatsApp du site vit encore, **a** sinon. Hugo
relit, et memobook.fr publie le même texte.

Réponse :

### D7 — Les CGU disent « participants »

Les CGU parlent de « participants » et d'« utilisateurs » ; l'app, la FAQ et
le vocabulaire disent « co-voyageurs ».

- **a.** Passer les CGU à « co-voyageurs » (et memobook.fr le même jour).
- **b.** Garder.

**Reco : a**, avec la prochaine republication des CGU (D4).

Réponse :

---

## Crédit du jour

### D8 — Corriger un souvenir quand le pot est vide

Une correction au clavier coûte ce qu'elle ajoute (75 ms par caractère). Pot
vide, elle est donc refusée : on dicte 5 minutes, la fiche arrive, on veut
corriger un nom propre — « Le crédit du jour est épuisé, réessaie demain ».
C'est pourtant le moment naturel pour corriger.

- **a.** Toujours refusée, comme aujourd'hui.
- **b.** Gratuite jusqu'à 200 caractères ajoutés par fiche, payante au-delà.
- **c.** Toujours gratuite.

**Reco : b** — on corrige sans payer, on ne peut pas écrire un récit entier par
ce biais.

Réponse :

### D9 — Un vocal muet consomme-t-il le crédit ?

Un vocal sans parole (téléphone en poche, silence) est décompté à sa durée.
Depuis cette QA, MEMO dit qu'il n'a rien entendu au lieu de se taire.

- **a.** Le rendre au pot quand la transcription est vide.
- **b.** Le laisser compté : quelques secondes, en général.

**Reco : b.** À revoir si des voyageurs s'en plaignent.

Réponse :

### D10 — Le texte « hors ligne » de la FAQ

« Si le crédit du jour est déjà épuisé quand ils arrivent, ils attendent sur
ton téléphone et partent d'eux-mêmes le lendemain » — faux pour un vocal de
plus de 5 minutes ou un texte de plus de 4 000 caractères : eux attendent
l'illimité.

- **a.** Ajouter : « Un enregistrement plus long que le crédit d'une journée
  attend, lui, que tu passes en illimité. »
- **b.** Laisser : le cas est rare.

**Reco : a.**

Réponse :

---

## Conversation, voyage, réglages

### D11 — Ouvrir hors ligne un voyage jamais ouvert sur ce téléphone

Hors ligne, un voyage qu'on n'a jamais ouvert sur cet appareil (rejoint
ailleurs, ou d'une installation neuve) n'affiche qu'un squelette et « Pas de
réseau. Là, c'est vraiment le wifi. » : pas de bouton vers la conversation,
alors qu'on pourrait y raconter hors ligne. (Voisin de T239.)

- **a.** Ouvrir l'écran à partir de ce que la carte de l'accueil connaît
  (titre, dates, photo) et donner accès au fil.
- **b.** Garder l'écran d'erreur.

**Reco : a.**

Réponse :

### D12 — Supprimer un souvenir efface-t-il son vocal ?

Supprimer un souvenir le retire du carnet, mais son fichier (le vocal, la
photo) reste sur nos serveurs, rattaché à rien. La suppression du compte,
elle, efface tout.

- **a.** Effacer aussi le fichier.
- **b.** Le garder (une restauration resterait possible, mais rien ne la
  propose).

**Reco : a** — c'est ce qu'on attend d'un « supprimer » au sens du RGPD.

Réponse :

### D13 — Couper les notifications d'un voyage coupe celles de tout le monde

Les interrupteurs de la feuille « Notifications » d'un voyage valent pour
**tous ses co-voyageurs** : si l'un coupe la relance d'écriture, personne ne
la reçoit plus. Et les notifications du compte (vacances scolaires,
anniversaire, rappel de renouvellement) n'ont aucun interrupteur dans l'app :
seuls les réglages d'iOS les coupent.

- **a.** Rien à changer : le réglage d'iOS suffit.
- **b.** Des interrupteurs propres à chaque co-voyageur, et une ligne
  « Notifications » au profil pour celles du compte.
- **c.** Seulement la ligne du profil.

**Reco : b** — un réglage qu'on change chez les autres sans le savoir est une
mauvaise surprise. Maquette nécessaire.

Réponse :

---

## Textes à corriger dans Figma

### D14 — « Découvre-les et répond »

Personnalisations › Extras › Quiz : « Découvre-les et **répond** lors de la
réception de ton carnet. » — **réponds**.

**Reco** : corriger dans Figma, l'app suit.

Réponse :

### D15 — Un vouvoiement et une majuscule

- Paywall, écran 2 : « la phrase du guide qui **vous** a fait rire » → « qui
  **t'**a fait rire » (R9 ; ou « vous » de groupe, voulu ?).
- Profil : la feuille s'intitule « Mon **A**bonnement », la ligne qui l'ouvre
  « Mon abonnement ». À joindre à T213 (les majuscules à l'anglaise).

**Reco** : « qui t'a fait rire », « Mon abonnement ».

Réponse :

### D16 — L'annonce VoiceOver de l'arrêt à la limite

Quand l'enregistrement s'arrête net au bout du crédit, VoiceOver annonçait
« Limite du jour atteinte. Ton vocal est envoyé. » — faux hors ligne, où le
vocal attend. La QA l'a remplacée par « Limite du jour atteinte. Ton vocal
est gardé. » (ce texte n'a pas de maquette).

**Reco** : valider tel quel.

Réponse :

---

## Ce qui a été décidé sans toi, pour information

Des choix par défaut, réversibles, pris pendant la QA. Rien à répondre, sauf
désaccord.

- **Un abonnement « actif » sans nouvelles d'Apple depuis trois jours après sa
  date de renouvellement n'ouvre plus l'illimité.** C'est le cas d'un
  événement d'expiration perdu, qui donnait l'illimité à vie. Un abonné
  vraiment renouvelé le retrouve dès que l'app renvoie sa transaction.
- **Un vocal refusé par le plafond anti-abus du fil** (150 tours par jour et
  par voyage) attend le lendemain sur le téléphone, comme le crédit du jour,
  au lieu d'être effacé — le message dit déjà « Reviens demain ».
- **Un vocal refusé parce que la session a expiré** attend la reconnexion au
  lieu d'être effacé.
- **Le délai de grâce d'Apple** (carte expirée, prélèvement retenté) affiche
  l'abonnement comme actif dans le profil, et ne déclenche plus le rappel
  « se renouvelle dans 3 jours ».
- **Les dates de voyage** ne se décalent plus d'un jour pour un voyageur plus
  à l'ouest qu'au moment de la saisie (Londres, Lisbonne, New York) : la
  notification de fin de voyage partait la veille.
