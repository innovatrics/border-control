# Smart Corridors & e-Gates

Docker Compose stack for the Smart Corridors and e-Gates solution.

## Prerequisites

- Docker Engine ≥ 20.10 + Compose plugin
- `secrets/iengine.lic` — from [Innovatrics Customer Portal](https://customerportal.innovatrics.com)

### Registry login

```bash
docker login registry.gitlab.com
docker login registry.dot.innovatrics.com -u 'inno-border-control+puller' -p '<token>'
```

## Usage

```bash
bash run.sh            # start
bash stop.sh           # stop, keep data
bash factory-reset.sh  # stop + wipe everything
```

## Endpoints

| Service | URL | Credentials |
|---------|-----|-------------|
| Corridor dashboard | http://localhost:8095 | — |
| Hub GraphQL | http://localhost:8090/corridor-foundation/graphql | — |
| Hub GraphiQL | http://localhost:8090/corridor-foundation/graphiql | — |
| CIGS health | http://localhost:8096/actuator/health | — |
| RabbitMQ | http://localhost:15672 | guest / guest |
| MinIO | http://localhost:9001 | minioadmin / minioadmin |
| pgAdmin | http://localhost:7070 | admin@admin.com / Test1234 |

## Configuration

### `.env` — image versions

| Variable | Description |
|----------|-------------|
| `CIGS_VERSION` | Corridor Identity Grouping Service version |
| `HUB_VERSION` | Smart Corridors & e-Gates Hub version |
| `FRONTEND_VERSION` | Frontend image tag |
| `FRONTEND_PORT` | Dashboard port (default 8095) |

### `.env.hub` — Hub wiring

| Group | Key variables |
|-------|---------------|
| Watchlists | `VPP_ADAPTER_ALLOWED_WATCHLISTS` — watchlist IDs that grant GREEN clearance (comma-separated) |
| Units | `FOUNDATION_UNITS_0_*` — corridor/e-gate unit definitions with their camera IDs |
| Storage | `STORAGE_S3_BUCKET`, credentials |

`HOST_S3_IP` — set this to your host LAN IP so the browser can load face crop thumbnails from MinIO directly. Defaults to in-network `minio` (thumbnails won't load outside Docker without it).
