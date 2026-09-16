#!/usr/bin/env tsx
/**
 * La chaîne de paiement de bout en bout, avec le vrai Stripe en mode test.
 *
 *   npm run stripe:e2e
 *
 * **Ce que la suite de tests ne peut pas couvrir.** `test/payments.test.ts`
 * passe par `FakePaymentGateway` : ni la création d'intention chez Stripe, ni
 * la vérification de signature du webhook n'y sont exercées pour de vrai. Ce
 * script les exerce, en créant un vrai paiement de test et en le payant avec
 * la carte 4242.
 *
 * Il suppose deux choses lancées à côté :
 *
 *   npm run dev
 *   stripe listen --forward-to localhost:3000/v1/webhooks/stripe
 *
 * Le `whsec_…` qu'affiche `stripe listen` doit être celui de `.env` — c'est la
 * panne numéro un, et le script le dit explicitement s'il la rencontre.
 *
 * ⚠️ Il écrit dans la base pointée par `DATABASE_URL` : un compte, un carnet,
 * un rendu et une commande. À lancer sur la base de développement.
 */
import { PrismaClient } from "@prisma/client";
import Stripe from "stripe";

const API = "http://localhost:3000";

/**
 * Deux connexions, pas plus.
 *
 * Le pooler Supabase en mode session n'accorde que **15 clients au total**, et
 * le serveur de dev en tient déjà une petite dizaine (Prisma + pg-boss). Un
 * script de vérification qui ouvre le pool par défaut de Prisma — cœurs × 2 + 1
 * — fait basculer le serveur d'à côté, et l'erreur tombe alors sur une route au
 * hasard. Deux suffisent : le script est séquentiel.
 */
function scriptDatabaseUrl(): string {
  const raw = process.env["DATABASE_URL"];
  if (!raw) throw new Error("DATABASE_URL absente de l'environnement");
  const url = new URL(raw);
  url.searchParams.set("connection_limit", "1");
  return url.toString();
}

const prisma = new PrismaClient({ datasourceUrl: scriptDatabaseUrl() });

function readEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} absente de l'environnement`);
  return value;
}

async function api<T>(
  path: string,
  init: { method: string; body?: unknown; token?: string },
): Promise<T> {
  const response = await fetch(`${API}${path}`, {
    method: init.method,
    headers: {
      "content-type": "application/json",
      ...(init.token ? { authorization: `Bearer ${init.token}` } : {}),
    },
    ...(init.body ? { body: JSON.stringify(init.body) } : {}),
  });

  const text = await response.text();
  if (!response.ok) {
    throw new Error(`${init.method} ${path} → ${response.status} : ${text.slice(0, 400)}`);
  }
  return JSON.parse(text) as T;
}

function step(n: number, label: string) {
  console.log(`\n\x1b[1m${n}. ${label}\x1b[0m`);
}

async function main() {
  const stripe = new Stripe(readEnv("STRIPE_SECRET_KEY"));

  step(1, "Ouvrir un compte");
  const email = `e2e-${Date.now()}@memobook.test`;
  const auth = await api<{ token: string; account: { id: string } }>("/v1/auth/signup", {
    method: "POST",
    body: { email, password: "carnet2026", firstName: "E2E" },
  });
  console.log(`   compte ${auth.account.id}`);

  step(2, "Créer un carnet");
  const memo = await api<{ id: string }>("/v1/memos", {
    method: "POST",
    token: auth.token,
    body: { title: "Rome 2026 — test Stripe", authors: "E2E", theme: "voyage" },
  });
  console.log(`   carnet ${memo.id}`);

  step(3, "Poser un rendu prêt (on teste l'argent, pas la composition)");
  const render = await prisma.render.create({
    data: { memoId: memo.id, status: "ready", pdfUrl: "https://pdf.example.test/e2e.pdf" },
  });
  console.log(`   rendu ${render.id}`);

  step(4, "Commander → crée une VRAIE intention chez Stripe");
  const order = await api<{
    id: string;
    status: string;
    payment: { clientSecret: string; amountCents: number; currency: string };
  }>(`/v1/memos/${memo.id}/orders`, {
    method: "POST",
    token: auth.token,
    body: {
      renderId: render.id,
      copies: 1,
      shipping: {
        name: "Clara Martin",
        line1: "12 rue des Lilas",
        postalCode: "44000",
        city: "Nantes",
        country: "FR",
      },
    },
  });

  const intentId = order.payment.clientSecret.split("_secret")[0]!;
  // Gardé pour l'étape 10 : le même carnet, commandé une seconde fois, coûte le
  // même prix — et c'est de ce total qu'on déduira les 30 € de cagnotte.
  const cardTotal = order.payment.amountCents;
  console.log(`   commande ${order.id} — statut « ${order.status} »`);
  console.log(
    `   intention ${intentId} — ${(order.payment.amountCents / 100).toFixed(2)} ${order.payment.currency.toUpperCase()}`,
  );

  step(5, "Vérifier que Stripe la connaît vraiment");
  const remote = await stripe.paymentIntents.retrieve(intentId);
  console.log(`   Stripe dit : ${remote.status}, ${remote.amount} centimes, livemode=${remote.livemode}`);
  if (remote.metadata["orderId"] !== order.id) {
    throw new Error("metadata.orderId ne correspond pas à la commande");
  }
  console.log(`   metadata.orderId ✓`);

  step(6, "Payer avec la carte de test 4242");
  await stripe.paymentIntents.confirm(intentId, {
    payment_method: "pm_card_visa",
    return_url: "https://memo-book.com/retour",
  });
  console.log("   confirmée — Stripe envoie maintenant son webhook");

  step(7, "Attendre que le webhook fasse passer la commande en submitted");
  let final = null;
  for (let attempt = 1; attempt <= 20; attempt += 1) {
    await new Promise((resolve) => setTimeout(resolve, 1000));
    final = await prisma.printOrder.findUniqueOrThrow({ where: { id: order.id } });
    process.stdout.write(`   ${attempt}s → ${final.status}\r`);
    if (final.status !== "draft") break;
  }

  console.log("");
  if (!final || final.status !== "submitted") {
    throw new Error(
      `La commande est restée en « ${final?.status} ». ` +
        "Vérifie que `stripe listen` tourne et que STRIPE_WEBHOOK_SECRET est celui qu'il affiche.",
    );
  }

  console.log(`\n\x1b[32m✅ Commande par carte : chaîne vérifiée\x1b[0m`);
  console.log(`   statut      : ${final.status}`);
  console.log(`   submittedAt : ${final.submittedAt?.toISOString()}`);
  console.log(`   montant     : ${final.amountCents} centimes`);
  console.log(`   intention   : ${final.stripePaymentIntentId}`);

  // Le double `stripe listen` livre chaque événement deux fois : si la date
  // n'a pas bougé, la garde d'idempotence a tenu en conditions réelles.
  const submittedAt = final.submittedAt?.toISOString();
  await new Promise((resolve) => setTimeout(resolve, 3000));
  const again = await prisma.printOrder.findUniqueOrThrow({ where: { id: order.id } });
  console.log(
    again.submittedAt?.toISOString() === submittedAt
      ? "   idempotence : ✅ la date n'a pas bougé après les livraisons suivantes"
      : "   idempotence : ❌ submittedAt a été réécrite",
  );

  // -------------------------------------------------------------------------
  // Deuxième scénario : la cagnotte
  // -------------------------------------------------------------------------

  step(8, "Recharger la cagnotte de 30 €");
  const topup = await api<{ clientSecret: string; amountCents: number }>(
    "/v1/wallet/topup",
    { method: "POST", token: auth.token, body: { amountCents: 3000 } },
  );
  const topupIntent = topup.clientSecret.split("_secret")[0]!;
  console.log(`   intention ${topupIntent} — 30,00 EUR`);

  const beforeTopup = await prisma.account.findUniqueOrThrow({
    where: { id: auth.account.id },
  });
  if (beforeTopup.walletBalanceCents !== 0) {
    throw new Error("La cagnotte a bougé avant l'encaissement — elle ne devrait pas.");
  }
  console.log("   solde avant paiement : 0 centime ✓ (rien n'est crédité d'avance)");

  step(9, "Payer la recharge, et attendre que le webhook crédite");
  await stripe.paymentIntents.confirm(topupIntent, {
    payment_method: "pm_card_visa",
    return_url: "https://memo-book.com/retour",
  });

  let credited = 0;
  for (let attempt = 1; attempt <= 20; attempt += 1) {
    await new Promise((resolve) => setTimeout(resolve, 1000));
    const account = await prisma.account.findUniqueOrThrow({
      where: { id: auth.account.id },
    });
    credited = account.walletBalanceCents;
    process.stdout.write(`   ${attempt}s → ${credited} centimes\r`);
    if (credited > 0) break;
  }
  console.log("");

  if (credited !== 3000) {
    throw new Error(`La cagnotte affiche ${credited} centimes au lieu de 3000.`);
  }

  const ledger = await prisma.walletEntry.findMany({
    where: { accountId: auth.account.id },
    orderBy: { createdAt: "asc" },
  });
  console.log(`   ✅ cagnotte créditée : ${credited} centimes`);
  console.log(`   écritures au registre : ${ledger.length}`);
  console.log(`   solde recopié sur l'écriture : ${ledger[0]?.balanceAfterCents}`);
  console.log(`   événement Stripe tracé : ${ledger[0]?.stripeEventId ?? "aucun"}`);

  step(10, "Commander un second carnet : 30 € de cagnotte, la carte pour le reste");
  const second = await prisma.render.create({
    data: { memoId: memo.id, status: "ready", pdfUrl: "https://pdf.example.test/e2e-2.pdf" },
  });

  // **Les deux rails se partagent la note.** La cagnotte n'est pas un mode de
  // paiement qu'on choisit : elle couvre ce qu'elle peut, et l'intention Stripe
  // ne porte que le reste. Il n'y a donc rien à refuser — 30 € sur un carnet à
  // 103,10 € n'est pas un solde insuffisant, c'est un acompte.
  const partial = await api<{
    id: string;
    status: string;
    payment: { paidFromWallet: boolean; clientSecret?: string; amountCents: number };
  }>(`/v1/memos/${memo.id}/orders`, {
    method: "POST",
    token: auth.token,
    body: {
      renderId: second.id,
      copies: 1,
      shipping: {
        name: "Clara Martin",
        line1: "12 rue des Lilas",
        postalCode: "44000",
        city: "Nantes",
        country: "FR",
      },
    },
  });

  const expectedCard = cardTotal - 3000;
  console.log(
    `   commande ${partial.id} — ${(partial.payment.amountCents / 100).toFixed(2)} € à la carte`,
  );

  if (partial.payment.paidFromWallet) {
    throw new Error("La cagnotte ne couvrait que 30 € : la carte devait payer le reste.");
  }
  if (partial.payment.amountCents !== expectedCard) {
    throw new Error(
      `L'intention porte ${partial.payment.amountCents} centimes au lieu de ${expectedCard} : ` +
        "la déduction de cagnotte n'a pas été appliquée au montant débité.",
    );
  }

  // Le débit est écrit **à la création de la commande**, pas au retour de
  // Stripe : c'est ce qui empêche la même somme de couvrir deux commandes
  // parties en même temps.
  const drained = await prisma.account.findUniqueOrThrow({
    where: { id: auth.account.id },
  });
  if (drained.walletBalanceCents !== 0) {
    throw new Error(
      `La cagnotte affiche ${drained.walletBalanceCents} centimes : les 30 € auraient dû être débités.`,
    );
  }

  const debit = await prisma.walletEntry.findFirstOrThrow({
    where: { accountId: auth.account.id, kind: "order_payment" },
  });
  if (debit.amountCents !== -3000 || debit.printOrderId !== partial.id) {
    throw new Error("Le débit de cagnotte n'est pas rattaché à la bonne commande.");
  }

  console.log(`   cagnotte vidée : ${debit.amountCents} centimes, rattachés à la commande ✓`);

  console.log(`\n\x1b[32m✅ Cagnotte : chaîne vérifiée\x1b[0m`);
  console.log("   crédit par webhook ✓  déduction sur la commande suivante ✓");
  console.log(`\n\x1b[1mTout le système de paiement de test est opérationnel.\x1b[0m`);
}

main()
  .catch((error) => {
    console.error(`\n\x1b[31m❌ ${error instanceof Error ? error.message : error}\x1b[0m`);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
