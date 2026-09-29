/**
 * La feuille de bord MemoBook — le script côté Google Sheets (T72).
 *
 * L'API n'écrit pas dans la feuille : elle envoie un JSON à ce script, déployé
 * en **application web**, et c'est lui qui pose les lignes. Voir
 * `backend/src/services/statsExport.ts` pour ce qui arrive.
 *
 * Mise en place, une fois :
 *
 *   1. Crée un Google Sheet vide — « MemoBook · Tableau de bord ».
 *   2. Extensions → Apps Script, colle ce fichier à la place de `Code.gs`.
 *   3. Dans « Paramètres du projet » → « Propriétés du script », ajoute
 *      `SECRET` avec une longue chaîne au hasard.
 *   4. Déployer → Nouveau déploiement → Application web :
 *      exécuter en tant que **moi**, accès **tout le monde** (le secret filtre).
 *   5. Copie l'URL du déploiement dans `STATS_SHEET_WEBHOOK_URL` sur Railway,
 *      et le secret dans `STATS_SHEET_SECRET`. Redéploie l'API.
 *   6. `npm run stats:push` depuis `backend/` pour remplir les onglets sans
 *      attendre le passage de 4 h 20.
 *
 * Trois onglets, créés au premier envoi :
 *
 *   - **Relevés** : une ligne par jour, une colonne par chiffre — de quoi
 *     tracer des courbes avec un graphique Sheets ordinaire ;
 *   - **Résiliations** : une ligne par raison de départ, à l'instant où elle
 *     est donnée ;
 *   - **Carnets à livrer** : réécrit à chaque relevé — les commandes parties et
 *     pas encore livrées, avec leur adresse et leur suivi.
 *
 * Un quatrième onglet, **Tableau de bord**, est laissé à la main : des
 * formules sur « Relevés » (`=INDEX(Relevés!B:B; COUNTA(Relevés!B:B))` pour
 * la dernière valeur), et les graphiques qu'on veut.
 */

var SNAPSHOT_COLUMNS = [
  ["generatedAt", "Relevé"],
  ["accounts.total", "Utilisateurs"],
  ["accounts.newLast7Days", "Nouveaux (7 j)"],
  ["accounts.subscribed", "Abonnés"],
  ["trips.total", "Voyages"],
  ["trips.ongoing", "Carnets en cours"],
  ["trips.upcoming", "Voyages à venir"],
  ["trips.past", "Voyages passés"],
  ["trips.composed", "Carnets composés"],
  ["orders.total", "Carnets commandés"],
  ["orders.inProgress", "Commandes en cours"],
  ["orders.draft", "Brouillons"],
  ["orders.submitted", "Soumises"],
  ["orders.inProduction", "En production"],
  ["orders.shipped", "Expédiées"],
  ["orders.delivered", "Livrées"],
  ["orders.cancelled", "Annulées"],
  ["orders.copies", "Exemplaires"],
  ["orders.revenueEuros", "Chiffre d'affaires (€)"],
  ["subscriptions.active", "Abonnements actifs"],
  ["subscriptions.cancelled", "Abonnements résiliés"],
  ["subscriptions.expired", "Abonnements arrivés à terme"],
  ["memories.total", "Souvenirs racontés"],
  ["memories.photos", "Photos"],
];

var CANCELLATION_COLUMNS = ["Date", "Compte", "Raison", "Abonnement actif"];

var DELIVERY_COLUMNS = [
  "Commande",
  "Voyage",
  "Statut",
  "Exemplaires",
  "Pages",
  "Montant (€)",
  "Destinataire",
  "Ville",
  "Pays",
  "Suivi",
  "Soumise le",
  "Expédiée le",
];

/** Le point d'entrée : un POST par envoi. */
function doPost(request) {
  var payload;
  try {
    payload = JSON.parse(request.postData.contents);
  } catch (error) {
    return reply({ ok: false, error: "JSON illisible" });
  }

  var secret = PropertiesService.getScriptProperties().getProperty("SECRET") || "";
  if (secret && payload.secret !== secret) {
    return reply({ ok: false, error: "secret refusé" });
  }

  var lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    if (payload.type === "snapshot") {
      writeSnapshot(payload.snapshot);
      writeDeliveries(payload.snapshot.deliveries || []);
      writeReasons(payload.snapshot.subscriptions.cancellationReasons || {});
    } else if (payload.type === "cancellation") {
      writeCancellation(payload);
    } else {
      return reply({ ok: false, error: "type inconnu : " + payload.type });
    }
  } finally {
    lock.releaseLock();
  }

  return reply({ ok: true });
}

/** Un GET dit seulement que le script est là — pratique pour vérifier l'URL. */
function doGet() {
  return reply({ ok: true, message: "MemoBook · feuille de bord" });
}

function reply(body) {
  return ContentService.createTextOutput(JSON.stringify(body)).setMimeType(
    ContentService.MimeType.JSON
  );
}

function sheetNamed(name, headers) {
  var spreadsheet = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = spreadsheet.getSheetByName(name);
  if (!sheet) {
    sheet = spreadsheet.insertSheet(name);
  }
  if (sheet.getLastRow() === 0) {
    sheet.appendRow(headers);
    sheet.getRange(1, 1, 1, headers.length).setFontWeight("bold");
    sheet.setFrozenRows(1);
  }
  return sheet;
}

function valueAt(object, path) {
  var parts = path.split(".");
  var value = object;
  for (var i = 0; i < parts.length; i++) {
    if (value === null || value === undefined) return "";
    value = value[parts[i]];
  }
  return value === null || value === undefined ? "" : value;
}

/** Une ligne par relevé. Deux relevés le même jour : le second remplace le premier. */
function writeSnapshot(snapshot) {
  var sheet = sheetNamed(
    "Relevés",
    SNAPSHOT_COLUMNS.map(function (column) {
      return column[1];
    })
  );
  var row = SNAPSHOT_COLUMNS.map(function (column) {
    var value = valueAt(snapshot, column[0]);
    return column[0] === "generatedAt" ? new Date(value) : value;
  });

  var lastRow = sheet.getLastRow();
  if (lastRow > 1) {
    var previous = sheet.getRange(lastRow, 1).getValue();
    if (previous instanceof Date && sameDay(previous, row[0])) {
      sheet.getRange(lastRow, 1, 1, row.length).setValues([row]);
      return;
    }
  }
  sheet.appendRow(row);
}

function sameDay(a, b) {
  return (
    a.getUTCFullYear() === b.getUTCFullYear() &&
    a.getUTCMonth() === b.getUTCMonth() &&
    a.getUTCDate() === b.getUTCDate()
  );
}

/** Une raison de départ, à l'instant où elle est donnée. */
function writeCancellation(message) {
  var sheet = sheetNamed("Résiliations", CANCELLATION_COLUMNS);
  sheet.appendRow([
    new Date(message.at),
    message.account || "",
    message.reason || "(sans raison)",
    message.hadActiveSubscription ? "oui" : "non",
  ]);
}

/** Le cumul des raisons, sous la table des départs — recalculé à chaque relevé. */
function writeReasons(reasons) {
  var sheet = sheetNamed("Résiliations", CANCELLATION_COLUMNS);
  var keys = Object.keys(reasons);
  if (keys.length === 0) return;

  // Le cumul vit à droite de la table, à partir de la colonne F, et se
  // réécrit en entier.
  sheet.getRange(1, 6, Math.max(sheet.getLastRow(), keys.length + 1), 2).clearContent();
  sheet.getRange(1, 6, 1, 2).setValues([["Raison", "Total"]]).setFontWeight("bold");
  var rows = keys.map(function (key) {
    return [key, reasons[key]];
  });
  sheet.getRange(2, 6, rows.length, 2).setValues(rows);
}

/** Les carnets à livrer : la table est réécrite à chaque relevé. */
function writeDeliveries(deliveries) {
  var sheet = sheetNamed("Carnets à livrer", DELIVERY_COLUMNS);
  if (sheet.getLastRow() > 1) {
    sheet.getRange(2, 1, sheet.getLastRow() - 1, DELIVERY_COLUMNS.length).clearContent();
  }
  if (deliveries.length === 0) return;

  var rows = deliveries.map(function (delivery) {
    return [
      delivery.orderId,
      delivery.tripTitle,
      delivery.status,
      delivery.copies,
      delivery.pageCount,
      delivery.amountEuros === null ? "" : delivery.amountEuros,
      delivery.recipient,
      delivery.city,
      delivery.country,
      delivery.trackingUrl || "",
      delivery.submittedAt ? new Date(delivery.submittedAt) : "",
      delivery.shippedAt ? new Date(delivery.shippedAt) : "",
    ];
  });
  sheet.getRange(2, 1, rows.length, DELIVERY_COLUMNS.length).setValues(rows);
}
