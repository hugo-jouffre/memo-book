# Règles R8 du build Release. Vide pour l'instant : chaque bibliothèque qui en
# demande (kotlinx.serialization, Stripe, Play Billing) arrive avec les siennes.
# La CI compile aussi le Release, pour qu'une règle manquante casse la PR et non
# l'envoi sur le Play Store.
#
# `:payments` (stripe-android 23, billing-ktx 9) n'en ajoute aucune : le
# 22/10/2026, le Release a été minifié avec le magasin, les deux feuilles et leur
# hôte branchés dans l'activité, sans classe manquante ni règle à écrire. Le
# module n'emploie ni réflexion ni sérialisation qui en demanderaient.
