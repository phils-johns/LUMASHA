# Déploiement LUMASHA Smart

Deux déploiements, une seule base de code :

```
┌──────────────────────────────┐        ┌──────────────────────────────┐
│  CAISSE (stand AR114)        │        │  SITE PUBLIC                 │
│  SQLite, hors ligne          │        │  lecture seule               │
│  hôte Node persistant        │        │  Netlify (serverless)        │
└──────────────┬───────────────┘        └──────────────┬───────────────┘
               │ publie l'instantané                    │ lit l'instantané
               └──────────────► Supabase ◄──────────────┘
```

| | Caisse | Site public |
|---|---|---|
| Base | fichier SQLite (`data/lumasha.db`) | Supabase (instantané) |
| Variable | `LUMASHA_BACKEND=sqlite` | `LUMASHA_BACKEND=supabase` |
| Hébergeur | VPS / Docker / Render / Fly / Railway | **Netlify** |
| Disque persistant | **obligatoire** | aucun |
| Écriture | oui (source de vérité) | **non** (lecture seule) |

---

## 1. Supabase — déjà prêt

Le projet `okfazchidjcakeotcult` contient déjà toutes les tables
(`orders`, `customers`, `payments`, `pose_logs`, `deliveries`,
`stock_movements`, `lumasha_state`, …).

- `lumasha_state` : instantané publié par la caisse (1 ligne, `id='current'`).
- RLS activée sans policy → **seule la clé secrète** peut lire/écrire.
  La clé publiable ne voit rien (vérifié).

Aucune action supplémentaire n'est requise côté Supabase.

---

## 2. Déployer le SITE PUBLIC sur Netlify

Le dossier à déployer est **`lumasha/`** (racine du projet Next.js).
`netlify.toml` y est déjà configuré : build `npm run build`, publish `.next`,
Node 22, `LUMASHA_BACKEND=supabase`, `NEXT_PUBLIC_WA_NUMBER`, `NEXT_PUBLIC_STAND`.

> ℹ️ Le site utilise des routes serveur (`/api/state`, `/api/track`) : il faut
> **laisser Netlify builder** le projet (intégration Git, archive ZIP, ou CLI
> `--build`). Un simple upload du dossier `.next` déjà compilé ne suffit pas.

### Option A — Archive ZIP (glisser-déposer, le plus simple)

1. Créer l'archive source (sans `node_modules/`, `.next/`, `data/`, `.env.local`) :

   ```powershell
   # depuis la racine du projet
   Compress-Archive -Path (Get-ChildItem -Exclude node_modules,.next,data,.env.local,*.db) -DestinationPath ..\lumasha-netlify-source.zip -Force
   ```

   Une archive prête à l'emploi est fournie : `lumasha-netlify-source.zip`.

2. Netlify → **Sites → Deploys → Deploy manually** → glisser l'archive.
   Netlify lit `netlify.toml`, installe les dépendances et lance le build.

### Option B — CLI Netlify (sans Git)

```powershell
cd lumasha
powershell -ExecutionPolicy Bypass -File deploy\deploy-public.ps1
```

Ou manuellement :

```bash
npx netlify-cli login            # ouvre le navigateur (1re fois)
npx netlify-cli link             # crée / associe le site
npx netlify-cli deploy --build --prod
```

### Option C — Git + interface Netlify

Pousser `lumasha/` sur GitHub/GitLab, puis « Add new site → Import an existing
project ». Netlify lit `netlify.toml` automatiquement.

### Variable à définir dans Netlify (OBLIGATOIRE)

Netlify → **Site configuration → Environment variables → Add a variable** :

| Nom | Valeur | Portée |
|---|---|---|
| `SUPABASE_SERVICE_ROLE_KEY` | *clé secrète du projet Supabase* | Builds + Functions |

`LUMASHA_BACKEND`, `SUPABASE_URL`, `NEXT_PUBLIC_WA_NUMBER` et `NEXT_PUBLIC_STAND`
sont déjà fournis par `netlify.toml`.

> ⚠️ Ne préfixez **jamais** cette variable par `NEXT_PUBLIC_` : elle doit rester
> côté serveur. Netlify ne l'expose pas au navigateur.

---

## 3. Publier depuis la caisse

La caisse pousse automatiquement un instantané vers Supabase après **chaque
écriture** (800 ms après une modification, ou à la validation d'une vente).
Rien à faire : il suffit que la caisse ait `SUPABASE_SERVICE_ROLE_KEY` et
`SUPABASE_URL` dans son environnement.

Pour forcer une publication immédiate (avant d'ouvrir le site) :

```bash
# caisse en cours d'exécution sur http://localhost:3000
curl -X PUT http://localhost:3000/api/state ^
  -H "Content-Type: application/json" ^
  -d "{\"state\":<état>, \"action\":\"sync\"}"
```

Ou plus simple : ouvrez le tableau de bord de la caisse → **Base de données** →
le badge « Passerelle Supabase active » doit apparaître, avec l'heure de
publication. Toute vente/pose/stock déclenche ensuite la publication.

Vérifier côté Supabase (éditeur SQL) :

```sql
select id, updated_at from lumasha_state;
```

---

## 4. Héberger la CAISSE (hôte persistant)

La caisse a besoin d'un **disque qui survit** (fichier SQLite). Choisir :

### Docker (recommandé)

```bash
cd lumasha
docker compose up -d --build
```

La base vit dans le volume `lumasha-data` (`/app/data/lumasha.db`).

Variables à passer (fichier `.env` à côté de `docker-compose.yml`) :

```env
LUMASHA_BACKEND=sqlite
SUPABASE_URL=https://okfazchidjcakeotcult.supabase.co
SUPABASE_SERVICE_ROLE_KEY=<clé secrète>
```

### VPS / Render / Fly / Railway

- Build : `npm ci && npm run build`
- Start : `node .next/standalone/server.js`
- **Monter un disque** sur `data/` et définir `LUMASHA_DB_PATH` (ex. `/data/lumasha.db`)
- Variables : `LUMASHA_BACKEND=sqlite`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`

### Sans hébergeur (le jour de la foire)

Un simple `npm run dev` (ou `npm run build && npm start`) sur un portable suffit :
la caisse fonctionne **hors ligne** (localStorage + file IndexedDB) et
synchronise Supabase dès que le réseau revient.

---

## 5. Vérifications rapides

| Test | Attendu |
|---|---|
| `GET /api/health` sur la caisse | `mode=internal`, `bridge.enabled=true` |
| `GET /api/health` sur le site public | `mode=public`, `ready=true` |
| `GET /api/state` sur le site public | `orders` vide, `stock` rempli |
| `GET /api/orders` sur le site public | **403** |
| `GET /api/track?number=…&phone=…` | la commande si publiée |

---

## Dépannage

- **Le site public ne montre aucun stock** → l'instantané n'a pas encore été
  publié. Ouvrez la caisse, faites une action, puis vérifiez
  `select updated_at from lumasha_state;`.
- **`bridge.enabled=false`** → `SUPABASE_SERVICE_ROLE_KEY` absente de
  l'environnement du processus (les fichiers `.env.local` ne sont **pas** lus par
  le serveur standalone : utilisez de vraies variables d'environnement).
- **Le build Netlify échoue sur Node** → `NODE_VERSION=22` est déjà dans
  `netlify.toml` ; vérifiez qu'aucun ancien réglage du site ne force Node 18.
- **`npm error notarget No matching version found for graceful-fs@4.2.12`**
  (échec à l'étape « Install dependencies ») → ancien verrou de dépendances
  pointant vers une version inexistante. Corrigé : `package.json` épingle
  `overrides.graceful-fs = "4.2.11"` et `package-lock.json` a été régénéré
  (`4.2.12` n'y apparaît plus). Redéployez avec ces deux fichiers à jour :
  ```powershell
  npm.cmd install        # régénère node_modules + package-lock.json
  npm.cmd run build      # vérifie que le build passe en local
  ```
  Si le site est déployé depuis une archive, ré-uploader le dossier `lumasha/`
  (sans `node_modules/`, `.next/`, `data/`, ni `.env.local`).
- **Projet Supabase en pause** → sur le plan gratuit, un projet inactif 7 jours
  est mis en pause. Le réactiver depuis le tableau de bord Supabase.
- **Le plugin Next.js n'est pas appliqué** (build CLI local) :
  `npm i -D @netlify/plugin-nextjs` puis ajouter dans `netlify.toml` :
  ```toml
  [[plugins]]
    package = "@netlify/plugin-nextjs"
  ```
