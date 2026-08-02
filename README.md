# labf-infra

Shared Docker infrastructure for the Lab F 11+ suite. Owned by nobody — apps reference these resources as `external`, and no single app's `docker compose down` affects them.

## What's here

| Resource | Type | Used by |
|----------|------|---------|
| `labf-net` | Docker bridge network | All app backends (hub, writing-buddy, vocab-master, story-sleuth) |
| `labf-db` | PostgreSQL 17 container | hub (identity data), story-sleuth (reading comprehension data) |

## Setup (once per host)

```bash
git clone https://github.com/DanWangDev/labf-infra.git
cd labf-infra
./bootstrap.sh
```

`bootstrap.sh` is idempotent — safe to re-run. If the network or container already exists, it leaves them alone.

## App database setup

When adding a new app, create its database inside `labf-db`:

```bash
docker exec labf-db createdb -U hub <app_db_name>
```

Then point the app at `postgres://hub:<password>@labf-db:5432/<app_db_name>`.

## Current databases

| Database | App |
|----------|-----|
| `hub` | 11plus-hub |
| `story_sleuth` | story-sleuth |

## Why not in an app repo?

Shared infrastructure has no natural owner among the apps. The hub was the original owner of `bootstrap.sh` when it only created `labf-net`, but as the shared stack grows (network, database, future services), a dedicated repo keeps the canonical source of truth in one place.
