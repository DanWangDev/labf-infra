# NAS Runner Setup — Shared GitHub Actions Runner for the Lab F 11+ Suite

Step-by-step guide for the **org-level** self-hosted runner that deploys every
Lab F app to the Synology NAS (DS918+, DSM 7.x — works on DSM 6.x too).

## 0. How it fits together

```
GitHub (CI success on main, in ANY DanWangDev repo)
        │  workflow_run (each repo's gated deploy workflow)
        ▼
actions-runner container on the NAS  ← polls GitHub for jobs (outbound HTTPS only)
        │  docker CLI via mounted /var/run/docker.sock
        ▼
NAS Docker daemon
        │  docker compose -f docker-compose.prod.yml pull && down && up -d
        ▼
hub / vocab-master / writing-buddy / story-sleuth containers
```

The runner is **shared by the whole org**: it registers against
`https://github.com/DanWangDev`, so any org repo can dispatch to it with
`runs-on: nas`. Today the consumers are the four deploy workflows (one per
app repo), all following the same gated pattern.

Everything needed to build the runner lives in [`nas-runner/`](../nas-runner):
`Dockerfile` (official `actions/runner` release tarball — no third-party
runner images), `entrypoint.sh`, and `docker-compose.yml`.

## 1. Prerequisites on the NAS

- **DSM 7.x** with the **Container Manager** package installed (DSM 6: the
  "Docker" package — identical for our purposes).
- **SSH enabled**: Control Panel → *Terminal & SNMP* → enable SSH (port 22).
- Your SSH user must be in the **administrators** group.
- **Accurate time**: Control Panel → *Regional Options* → *Time* → enable
  NTP sync. (The runner refuses to work with a skewed clock.)
- **Firewall**: the default DSM firewall already allows all outbound traffic —
  that's all the runner needs. No inbound rule required.
- ~1 GB free disk on `/volume1` and ~500 MB RAM headroom (DS918+ has 4 GB).
- **Docker Compose CLI is NOT needed on the NAS** — the runner container
  carries its own `docker compose` plugin and talks to the daemon via the
  socket. This sidesteps the Synology `docker compose` vs `docker-compose`
  version split entirely.

## 2. One-time: put the app checkouts on the NAS (the deploy targets)

Each app's deploy workflow runs `docker compose` in its own checkout, so all
of these must exist (with their production `.env`s — the runner never clones):

```bash
ssh admin@<nas-ip>
mkdir -p /volume1/docker
cd /volume1/docker

git clone https://github.com/DanWangDev/11plus-hub.git
git clone https://github.com/DanWangDev/vocab-master.git
git clone https://github.com/DanWangDev/writing-buddy.git
git clone https://github.com/DanWangDev/story-sleuth.git
git clone https://github.com/DanWangDev/labf-infra.git

# Each app checkout needs its production .env (gitignored). At minimum:
#   11plus-hub:      DB_PASSWORD, HUB_SESSION_SECRET, OIDC_COOKIE_KEYS,
#                    OIDC_SIGNING_KEY, HUB_CLIENT_SECRET, ADMIN_*
#   vocab-master:    OIDC_CLIENT_SECRET (+ its existing env needs)
#   writing-buddy:   its existing env needs
#   story-sleuth:    DATABASE_URL (+ its existing env needs)
```

> The runner only re-pulls images and restarts containers from these
> pre-existing checkouts. Update a checkout manually (`git pull`) when its
> compose/env templates change.

## 3. One-time: create the runner registration token on GitHub

1. GitHub → **DanWangDev org → Settings → Actions → Runners** (ORG level —
   that's what makes the runner available to every org repo).
2. **New self-hosted runner** → Linux → x64.
3. Copy the **registration token** from the `./config.sh --token ...` line
   (it expires after ~1 hour — you must complete step 4 within that window).

## 4. Build and start the runner container on the NAS

```bash
ssh admin@<nas-ip>
mkdir -p /volume1/docker/actions-runner
cd /volume1/docker/actions-runner

# Copy the runner definition from the labf-infra checkout (step 2):
cp -r /volume1/docker/labf-infra/nas-runner/* .

# Create the local .env with the token from step 3 (gitignored):
echo 'RUNNER_TOKEN=<paste-the-token>' > .env
echo 'RUNNER_ORG_URL=https://github.com/DanWangDev' >> .env
echo 'RUNNER_NAME=nas-01' >> .env
# RUNNER_LABELS defaults to "nas,deploy" — matches the deploy workflows' runs-on: nas

docker compose build
docker compose up -d
docker logs -f actions-runner
```

You should see:

```
√ Connected to GitHub
Listening for Jobs
```

Verify on GitHub: **Org → Settings → Actions → Runners** now shows
`nas-01` as **Idle** with labels `nas, deploy`.

## 5. Enable deploys

GitHub → **DanWangDev org → Settings → Secrets and variables → Actions →
Variables**:

- New variable `ENABLE_NAS_DEPLOY` = `true`

Every repo's deploy workflow checks this org variable, so one switch gates
the whole pipeline. Until it is set, deploy jobs intentionally **skip** (a
missing runner can never queue jobs forever).

## 6. Test the pipeline end to end

1. In any app repo: **Actions → CI → Run workflow** (branch `main`).
   A manual `workflow_dispatch` on `main` also triggers that repo's deploy
   workflow via `workflow_run`.
2. Watch the **Deploy to NAS** run: it picks up the `nas` label, runs
   `docker compose pull && down && up -d`, then polls the app's health
   endpoint via `docker exec <backend-container> wget ...` until healthy.
3. Confirm on the NAS: `docker ps` shows fresh containers, and each app's
   public URL responds.

If the health check fails, the job prints `docker compose logs --tail 50` —
start there.

## 7. Day-2 operations

| Task | How |
|------|-----|
| Runner status | Org → Settings → Actions → Runners; or `docker logs -f actions-runner` |
| Restart after NAS reboot | automatic — `restart: unless-stopped` |
| Rebuild after definition changes | `cd /volume1/docker/actions-runner && docker compose build && docker compose up -d` |
| Upgrade runner version | set `RUNNER_VERSION` in `docker compose build` args (bump the ARG default in the Dockerfile), rebuild. The runner also self-updates in its volume between releases |
| Remove/re-register | delete the runner in Org Settings, then `docker compose up -d --force-recreate` with a fresh token (the `--replace` flag in entrypoint.sh re-registers the same name) |
| Disable deploys everywhere | set `ENABLE_NAS_DEPLOY=false` (or delete the org variable) |
| Update an app checkout | `cd /volume1/docker/<repo> && git pull` (only when compose/env templates change) |

## 8. Security notes (read before going further)

- **Shared runner = org-wide dispatch boundary.** Anyone with push access to
  ANY DanWangDev repo can make a workflow target `runs-on: nas` and run
  arbitrary code on this runner — which has the NAS Docker socket. Keep all
  repos private, keep write access to the owner, and only add the `nas` label
  to gated main-branch deploy workflows. (Branch protection on `main` is
  recommended if the repos ever gain collaborators.)
- **Fork PRs cannot reach it.** The deploy workflows fire on `workflow_run`
  of CI on `main` only; fork PR CI runs are never on `main`.
- **Docker socket = root on the NAS.** The runner container mounts
  `/var/run/docker.sock` and runs as root *inside the container* — inherent
  to deploying via Docker. The mount also includes all of `/volume1/docker`;
  with the socket in hand this adds no meaningful extra surface, but be aware
  the runner can read every app's checkout.
- **The runner image is built from the official GitHub runner tarball** —
  do not swap it for third-party runner images without a supply-chain review.
- **No inbound ports.** The runner only polls out over HTTPS; nothing on your
  LAN can reach it.

## 9. Troubleshooting

| Symptom | Fix |
|---------|-----|
| `RUNNER_TOKEN: must be set` | The token is in `.env` next to the compose file — re-copy it; tokens expire after ~1h |
| Runner shows offline on GitHub | `docker logs -f actions-runner`; check NTP time sync on the NAS |
| Deploy job stays skipped | Set the org-level `ENABLE_NAS_DEPLOY=true` variable (step 5) |
| Deploy job queued forever | A runner with the `nas` label must be Idle; check labels or re-register |
| Health check fails after deploy | `docker logs <app-backend> --tail 50` on the NAS; the job also prints compose logs |
| `docker compose` not found inside runner | The image installs the compose plugin — rebuild the runner image if it's an old build |
