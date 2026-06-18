# Smart Corridors & e-Gates

Docker Compose stack for the Smart Corridors and e-Gates solution built on top of VPP (SmartFace).

## Structure

```
smart-corridors-and-e-gates/
├── vpp/                    # VPP platform — verbatim smartface/all-in-one, replace on upgrade
│   ├── docker-compose.yml
│   ├── run.sh
│   ├── .env
│   ├── .env.sfac
│   ├── .env.sfstation
│   └── sf_dependencies/    # postgres, rabbitmq, minio, pgadmin
├── docker-compose.yml      # solution services: hub, cigs, frontend
├── .env                    # image versions and registry
├── .env.hub                # Hub runtime wiring
├── secrets/
│   └── iengine.lic         # IFace license — gitignored, must be provided
├── run.sh
├── stop.sh
└── factory-reset.sh
```

## Prerequisites

- Docker Engine ≥ 20.10 + Compose plugin
- `secrets/iengine.lic` — from [Innovatrics Customer Portal](https://customerportal.innovatrics.com)

### Registry login

```bash
# VPP images
docker login registry.gitlab.com

# Solution images (CIGS, Hub, frontend)
docker login registry.dot.innovatrics.com -u 'inno-border-control+puller' -p '<token>'
```

## Usage

```bash
bash run.sh            # start full stack
bash stop.sh           # stop, keep volumes
bash factory-reset.sh  # stop + delete volumes + images
```

## Endpoints

| Service | URL | Credentials |
|---------|-----|-------------|
| Corridor dashboard | http://localhost:8095 | — |
| Hub GraphQL | http://localhost:8090/corridor-foundation/graphql | — |
| Hub GraphiQL | http://localhost:8090/corridor-foundation/graphiql | — |
| CIGS health | http://localhost:8096/actuator/health | — |
| SmartFace Station | http://localhost:8000 | — |
| VPP REST API | http://localhost:8098/api/v1 | — |
| VPP GraphQL | ws://localhost:8097/graphql | — |
| RabbitMQ | http://localhost:15672 | guest / guest |
| MinIO | http://localhost:9001 | minioadmin / minioadmin |
| pgAdmin | http://localhost:7070 | admin@admin.com / Test1234 |

## Configuration

### `.env` — solution image versions

| Variable | Description |
|----------|-------------|
| `HARBOR` | Harbor registry base URL |
| `CIGS_VERSION` | Corridor Identity Grouping Service version |
| `HUB_VERSION` | Smart Corridors & e-Gates Hub version |
| `FRONTEND_REGISTRY` | Frontend image registry |
| `FRONTEND_VERSION` | Frontend image tag |
| `FRONTEND_PORT` | Host port for the dashboard (default 8095) |

### `.env.hub` — Hub runtime wiring

All hostnames are container DNS names on `sf-network`, not `localhost`.

| Group | Key variables |
|-------|---------------|
| VPP source | `VPP_GRAPHQL_HOST=sf-graphql-api` port 80 — legacy `graphql-ws` |
| CIGS source | `CIGS_GRAPHQL_HOST=sceg-cigs` port 80 — modern `graphql-transport-ws` |
| RabbitMQ | `RABBITMQ_HOST=rmq` — must match `vpp/.env` |
| Watchlists | `VPP_ADAPTER_ALLOWED_WATCHLISTS` — comma-separated watchlist IDs that grant GREEN clearance |
| Units | `FOUNDATION_UNITS_0_*` — corridor/e-gate unit definitions with their camera IDs |
| Storage | MinIO bucket `corridor-foundation` — credentials must match `vpp/.env` |

`STORAGE_S3_ENDPOINT` is set in `docker-compose.yml`, not `.env.hub`, because it needs the host LAN IP so the browser can reach MinIO for presigned crop URLs. Set `HOST_S3_IP` in your environment to override the default (`minio`, which only works inside Docker).

### `vpp/.env` — VPP platform

Edit versions before first run:

```
SF_VERSION=v5_4.40.2
AC_VERSION=v5_1.14.0
SFS_VERSION=v5_1.32.0
```

Default DB is PostgreSQL. Switch to MS SQL by uncommenting the `mssql` block in `vpp/sf_dependencies/docker-compose.yml` and updating `vpp/.env`.

## Upgrading VPP

Replace all files in `vpp/` with the new `all-in-one/` from [innovatrics/smartface](https://github.com/innovatrics/smartface). The solution layer is unaffected.
