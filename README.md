# Border Control — Smart Corridors & e-Gates

All-in-one Docker Compose stack for the **Smart Corridors and e-Gates** solution.

Built on two independently versioned layers:

| Layer | Folder | What it runs |
|-------|--------|--------------|
| **VPP platform** | `vpp/` | SmartFace/VPP (~20 containers) + infrastructure (Postgres, RabbitMQ, MinIO) |
| **Solution** | `smart-corridors-and-e-gates/` | CIGS · Foundation Service · Corridor dashboard |

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| Docker Engine ≥ 20.10 + Compose plugin | Docker Desktop covers both |
| `secrets/iengine.lic` | IFace license — from Innovatrics Customer Portal |
| `secrets/cigs.env` | Contains `IFACE_SPEED_MATCH_PHRASE` — see `secrets/README.md` |

### Registry login

VPP images pull from the **public** GitLab registry (no VPN needed):

```bash
docker login registry.gitlab.com
# username / password from the Innovatrics Customer Portal
```

Solution images (CIGS, Foundation, frontend) pull from Harbor (also public):

```bash
docker login registry.dot.innovatrics.com -u 'inno-border-control+puller' -p '<token>'
```

---

## Quick start

```bash
# Drop your license files in secrets/ (see secrets/README.md)
# Then:
./run.sh
```

Once up:

| Service | URL | Credentials |
|---------|-----|-------------|
| **Corridor dashboard** | http://localhost:8095 | — |
| Foundation GraphiQL | http://localhost:8090/corridor-foundation/graphiql | — |
| SmartFace Station | http://localhost:8000 | — |
| VPP REST API | http://localhost:8098/api/v1 | — |
| VPP GraphQL | ws://localhost:8097/graphql | — |
| CIGS health | http://localhost:8096/actuator/health | — |
| RabbitMQ management | http://localhost:15672 | guest / guest |
| MinIO console | http://localhost:9001 | minioadmin / minioadmin |
| pgAdmin | http://localhost:7070 | admin@admin.com / Test1234 |

---

## Flags

```bash
./run.sh --vpp-only        # VPP platform only, no solution layer
./run.sh --no-cigs         # skip CIGS (Foundation still comes up)
./run.sh --no-frontend     # skip the dashboard
./run.sh --skip-verify     # skip post-boot smoke checks

./stop.sh                  # stop everything, keep data volumes
./stop.sh --wipe           # stop + delete volumes (re-seeds on next run)
```

Layers can also be run standalone:

```bash
./vpp/run.sh                             # platform only
./smart-corridors-and-e-gates/run.sh     # solution only (VPP must be up)
```

---

## Structure

```
border-control/
├── run.sh                              # master orchestrator
├── stop.sh
├── verify.sh                           # post-boot smoke checks
├── README.md
├── .gitignore
│
├── secrets/                            # ⚠ gitignored — drop your files here
│   ├── iengine.lic
│   ├── cigs.env
│   ├── cigs.env.example
│   └── README.md
│
├── db/
│   └── smartface-seed.dump             # pre-seeded SmartFace DB (cameras, GreenList)
│
├── lib/
│   └── gql-ws-probe.mjs               # GraphQL WS probe used by verify.sh
│
├── vpp/                               # VPP platform — replace whole folder on upgrade
│   ├── run.sh
│   ├── deps.yml                       # pgsql · rmq · minio · pgadmin
│   ├── vpp.yml                        # ~20 SmartFace/VPP containers
│   ├── .env                           # REGISTRY, SF_VERSION, DB, RMQ, S3 ...
│   ├── .env.sfstation
│   └── etc_rmq/
│       ├── enabled_plugins
│       └── rabbitmq.conf
│
└── smart-corridors-and-e-gates/       # solution layer
    ├── run.sh
    ├── corridor.yml                   # cigs · foundation · frontend
    ├── .env                           # HARBOR, CIGS_VERSION, FOUNDATION_VERSION, FRONTEND_*
    └── foundation/
        └── foundation.env            # Foundation Service runtime wiring
```

---

## Upgrading VPP

When a new VPP release ships:

1. Replace the contents of `vpp/` with the new version's files.
2. Update `vpp/.env` versions (`SF_VERSION`, `SFS_VERSION`, `AC_VERSION`).
3. Run `./run.sh` — the migration step upgrades the DB schema automatically.

The solution layer (`smart-corridors-and-e-gates/`) is unaffected.

---

## Configuration

Both layers have their own `.env` file. They share a common set of infrastructure defaults (RabbitMQ host/credentials, MinIO credentials) that must stay in sync — the shipped defaults match.

| File | Owns |
|------|------|
| `vpp/.env` | VPP image versions, DB engine, RabbitMQ, MinIO, S3 |
| `smart-corridors-and-e-gates/.env` | Harbor registry, CIGS/Foundation/Frontend versions, frontend port |
| `smart-corridors-and-e-gates/foundation/foundation.env` | Foundation Service runtime wiring (container DNS, RMQ, S3 bucket) |
