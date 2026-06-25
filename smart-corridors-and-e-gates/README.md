# Smart Corridors & e-Gates

Docker Compose stack for the Smart Corridors & e-Gates solution.

## Quick start

1. Clone this repository onto the target machine or server.
2. Obtain a license from [Innovatrics Customer Portal](https://customerportal.innovatrics.com) — see [License](#license) below.
3. Navigate to the `smart-corridors-and-e-gates/` folder.
4. Place `iengine.lic` into `./secrets/`.
5. Run:

```bash
bash run.sh
```

## License

The platform requires an `iengine.lic` file tied to the hardware of the machine it runs on.

To get your hardware ID, run:

```bash
docker run registry.gitlab.com/innovatrics/smartface/license-manager:3.2.7
```

Provide this ID when requesting a license from the [Customer Portal](https://customerportal.innovatrics.com).

Once you have the file, place it at `./secrets/iengine.lic` before running `run.sh`.

## Registry login

Before the first run, authenticate to both registries:

```bash
docker login registry.gitlab.com -u USER_NAME -p PASSWORD
docker login registry.dot.innovatrics.com -u USER_NAME -p PASSWORD
```

The registry USER_NAME and PASSWORD is provided separately by Innovatrics.

## Scripts

```bash
bash run.sh            # start all services
bash stop.sh           # stop, keep data
bash factory-reset.sh  # stop + wipe all containers, images, and volumes
```

## Endpoints

| Service            | URL                                          | Credentials                |
| ------------------ | -------------------------------------------- | -------------------------- |
| Corridor dashboard | http://localhost:8095                        | —                          |
| Hub GraphQL        | http://localhost:8090/corridor-hub/graphql   | —                          |
| Hub GraphiQL       | http://localhost:8090/corridor-hub/graphiql  | —                          |
| CIGS health        | http://localhost:8096/actuator/health        | —                          |
| VPP Admin          | http://localhost:8000                        | —                          |
| RabbitMQ           | http://localhost:15672                       | guest / guest              |
| MinIO              | http://localhost:9001                        | minioadmin / minioadmin    |
| pgAdmin            | http://localhost:7070                        | admin@admin.com / Test1234 |

## Configuration

### `.env` — service versions

| Variable           | Description                                |
| ------------------ | ------------------------------------------ |
| `CIGS_VERSION`     | Corridor Identity Grouping Service version |
| `HUB_VERSION`      | Smart Corridors & e-Gates Hub version      |
| `FRONTEND_VERSION` | Frontend image tag                         |
| `FRONTEND_PORT`    | Dashboard port (default `8095`)            |

### `.env.hub` — Hub wiring

| Group      | Key variables                                                                                                                 |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Watchlists | `VPP_ADAPTER_ALLOWED_WATCHLISTS` — watchlist IDs that grant GREEN clearance (comma-separated)                                  |
| Units      | `HUB_UNITS_0_*` — corridor/e-gate unit definitions with their camera IDs (empty/unset or `*` ⇒ the unit processes all cameras) |
| Storage    | `STORAGE_S3_BUCKET`, `STORAGE_S3_ACCESS_KEY`, `STORAGE_S3_SECRET_KEY`                                                          |

Face crop thumbnails stream through the Hub's in-service image proxy (`/corridor-hub/images`) — the browser fetches crops through the Hub, never directly from MinIO, so no host-networking setup is required. `STORAGE_S3_*` only configures the Hub's server-side access to MinIO (in-network `minio:9000`).
