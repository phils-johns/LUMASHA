# LUMASHA Smart

Application web PWA — caisse, stock, site public, app livreur.
Foire Internationale de Lomé 2026 — Stand AR114, Pavillon Agou.

## Stack
Next.js 16 (App Router, Turbopack) · TypeScript · Tailwind CSS v4 · Supabase · Lucide React · PWA

## Lancer en local
```bash
cp .env.example .env.local   # remplir les clés Supabase
npm install && npm run dev    # http://localhost:3000
```

## Hébergement
> ⚠️ **Les plateformes serverless ne conviennent pas** à la base SQLite : Vercel
> et Netlify ne persistent pas les fichiers écrits sur disque. Héberger la
> **caisse** sur un **serveur Node persistant** (VPS, Docker, Render, Fly,
> Railway) avec un volume monté pour les données.
>
> ✅ **Exception — site public** : en mode hybride (`LUMASHA_BACKEND=supabase`,
> voir plus bas), le site public est en lecture seule et lit Supabase ; il peut
> donc être hébergé sur Netlify/Vercel sans problème de disque.

### Docker (recommandé)
```bash
docker compose up -d --build      # http://localhost:3000
```
La base vit dans le volume `lumasha-data` (`/app/data/lumasha.db`) et survit aux
redémarrages et redéploiements. Variables publiques au build :
`NEXT_PUBLIC_SITE_URL`, `NEXT_PUBLIC_WA_NUMBER`, `NEXT_PUBLIC_STAND`.

### Sans Docker (standalone)
```bash
npm run build
cp -r public .next/standalone/ && cp -r .next/static .next/standalone/.next/
LUMASHA_DB_PATH=/var/lib/lumasha/lumasha.db node .next/standalone/server.js
```

### Render / Fly / Railway / VPS
- Build : `npm ci && npm run build` — Start : `node .next/standalone/server.js`.
- **Monter un disque persistant** sur le dossier de la base et définir
  `LUMASHA_DB_PATH` (ex. `/data/lumasha.db`).

### Sauvegarde / export
- `GET /api/export?format=json` → sauvegarde complète (état persisté).
- `GET /api/export?format=csv&entity=orders|customers|payments|poses|deliveries|stock|audit`
  → CSV par table (aucune donnée de coût / marge).
- Sauvegarder périodiquement le fichier `data/lumasha.db` (copie à chaud OK en mode WAL).

## Base de données (fichier SQLite)
Toutes les données métier (commandes, clients, paiements, stock, poses,
livraisons, journal) vivent dans **un seul fichier SQLite** — aucune dépendance
externe, fonctionne en local comme en hébergement.

- Moteur : `node:sqlite` (module natif Node ≥ 22.5) — rien à installer.
- Fichier : `data/lumasha.db` par défaut, surchargeable via `LUMASHA_DB_PATH`.
- Schéma + référentiel (films, designs, modèles, réglages) appliqués au premier
  démarrage ; mode WAL activé pour la robustesse.
- API REST sous `/api` : `state`, `orders`, `customers`, `payments`, `poses`,
  `deliveries`, `stock`, `stats`, `audit`, `health`, `export`.

### Lancer avec la base
```bash
npm run dev            # base dans ./data/lumasha.db
LUMASHA_DB_PATH=/var/lib/lumasha/lumasha.db npm run start   # volume persistant
```

## Synchronisation hors ligne
Le navigateur est l'écrivain unique : chaque modification est enregistrée
localement (`localStorage`) puis poussée vers la base SQLite (différée de 800 ms).
Si le réseau tombe, les opérations sont mises en file (IndexedDB) et rejouées au
retour de la connexion. Au démarrage, l'application hydrate son état depuis la
base ; si celle-ci est vide, elle l'amorce avec l'état local.

## Mode hybride : caisse SQLite ⇄ site public Supabase
Deux déploiements partagent la même base de code :

```
Caisse (SQLite, hors ligne, autoritaire)  ──publish──▶  Supabase (instantané)
                                                              │
Site public (Netlify/Vercel, lecture seule)  ◀──read──────────┘
```

- **Caisse** : `LUMASHA_BACKEND` vide ou `sqlite`. Le fichier SQLite reste la
  source de vérité ; chaque écriture publie en arrière-plan un instantané vers
  Supabase si la passerelle est configurée.
- **Site public** : `LUMASHA_BACKEND=supabase`. Lecture seule de l'instantané
  publié. Le back-office et l'app livreur sont masqués ; le suivi client passe
  par `GET /api/track?number=…&phone=…` (jamais l'état complet).

### Configuration
```bash
# Caisse (local / VPS / Docker)
LUMASHA_BACKEND=sqlite
SUPABASE_URL=https://<projet>.supabase.co
SUPABASE_SERVICE_ROLE_KEY=<clé service>   # serveur uniquement, jamais NEXT_PUBLIC_

# Site public (Netlify / Vercel)
LUMASHA_BACKEND=supabase
SUPABASE_URL=https://<projet>.supabase.co
SUPABASE_SERVICE_ROLE_KEY=<clé service>
```

Sans ces variables, la passerelle est **inerte** : l'application reste
strictement sur SQLite (aucune régression).

### Migrations Supabase (exécuter dans l'ordre)
1. `supabase/migrations/001_schema.sql` (schéma relationnel complet — optionnel en mode hybride)
2. `supabase/migrations/002_rls.sql` (RLS par rôle — optionnel en mode hybride)
3. `supabase/migrations/003_seed.sql`
4. `supabase/migrations/004_test_rules.sql`
5. `supabase/migrations/005_bridge.sql` — **requis** : table de la passerelle
   (`lumasha_state`), accès réservé à la clé service.

### Endpoints liés
- `GET /api/bridge` → état de la passerelle (aucune clé exposée).
- `GET /api/state` → mode `internal` ou `public` + état de la passerelle.
- `GET /api/track?number=…&phone=…` → suivi d'une commande (numéro exact + 8 derniers chiffres).
- Routes internes (`/api/orders`, `customers`, `payments`, `poses`, `deliveries`,
  `stock`, `stats`, `audit`, `export`) → **403 en mode public**.

### Déployer le site public sur Netlify
Guide complet : **[DEPLOIEMENT.md](./DEPLOIEMENT.md)**.

1. Créer le projet Supabase, exécuter les migrations, publier un premier
   instantané depuis la caisse.
2. Sur Netlify : `netlify.toml` est déjà prêt (build `npm run build`, publish
   `.next`, Node 22, `LUMASHA_BACKEND=supabase`). Lancer
   `deploy\deploy-public.ps1` ou `npx netlify-cli deploy --build --prod`.
3. Définir `SUPABASE_SERVICE_ROLE_KEY` dans l'interface Netlify
   (serveur uniquement). Aucun volume disque n'est nécessaire.

> ⚠️ Plan gratuit Supabase : projet **mis en pause après 7 jours d'inactivité**.
> Pendant la foire l'activité est quotidienne ; sinon prévoir un ping régulier.

## Données de démonstration
L'application fonctionne sans configuration : le magasin local
(`lib/store.tsx`, clé `lumasha_state_v2`) est la source de vérité côté navigateur,
synchronisée avec le fichier SQLite (voir « Base de données »). Sans base
joignable, elle reste pleinement utilisable en local :

- commandes, paiements, poses, livraisons, panier, stock et réglages ;
- synchronisation entre onglets du même navigateur ;
- file IndexedDB hors ligne pour les ventes, rejouée dès le retour réseau ;
- jeu de démonstration (4 commandes, 2 poses, 2 livraisons) au premier lancement.

Le bouton « Réinitialiser la démo » du tableau de bord recharge ce jeu.

## Modules P0 livrés
| Module | Description |
|---|---|
| Site public | Accueil, Trouver, Personnalisation (photo + cadrage), Commander, Suivi réel |
| Caisse Foire | Vente 3 étapes, paiement complet avant pose, mobile money avec référence |
| Commandes | Filtres, validation gérant, annulation motivée, ticket imprimable |
| Stock | Feuilles avant, 51 designs arrière, pertes par motif, arrivages |
| Poses | Journal, garantie, incidents, décrément automatique du stock |
| Tableau de bord | KPI, objectifs, clôture de caisse, exports CSV |
| App Livreur | Livraisons, code client à 4 chiffres, encaissement du solde |
| SQL | Schéma complet, RLS, triggers règles métier, seed, tests |

## Identité de marque
Le logo officiel `logo.png` est utilisé dans l'en-tête, le dock, les tickets
imprimables et les icônes PWA (`app/icon.png`, `public/icons/*`).

Voir `AGENTS.md` pour les règles permanentes et `ASSUMPTIONS.md` pour les
hypothèses de mise en œuvre.
