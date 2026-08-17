# Smart Corridors & e-Gates

Docker Compose stack for the Smart Corridors & e-Gates solution.

## Quick start

1. Clone this repository onto the target machine or server.
2. Obtain a license from [Innovatrics Customer Portal](https://customerportal.innovatrics.com) — see [License](#license) below.
3. Navigate to the `smart-corridors-and-e-gates/` folder.
4. Place `iengine.lic` into `./secrets/`.
5. Run:

```bash
bash start.sh
```

## License

The stack requires a single `iengine.lic` file tied to the hardware of the machine it runs on. The
same file licenses every service: the SmartFace/VPP platform and CIGS use its iengine block, while the
Hub and the operational-display frontend additionally require a `smart_corridor` block — without it
those two services are fail-closed and refuse to serve. Request a license with the `smart_corridor`
block enabled from the Customer Portal.

To get your hardware ID, run:

```bash
docker run registry.gitlab.com/innovatrics/smartface/license-manager:3.2.7
```

Provide this ID when requesting a license from the [Customer Portal](https://customerportal.innovatrics.com).

Once you have the file, place it at `./secrets/iengine.lic` before running `start.sh`.

## Registry login

Before the first run, authenticate to both registries:

```bash
docker login registry.gitlab.com -u USER_NAME -p PASSWORD
docker login registry.dot.innovatrics.com -u USER_NAME -p PASSWORD
```

The registry USER_NAME and PASSWORD is provided separately by Innovatrics.

## Scripts

```bash
bash start.sh          # start all services
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

### Zone notifications (Hub ≥ 0.4.0)

The Hub can derive `zone.*` notifications (person entered / left / moved, occupancy, counts,
avoiding-identification) with a **per-topic source switch** — each topic is computed from VPP
tracklets, CIGS identities, or the MCT track stream. `.env.hub` ships a commented example block;
`ZONE_PERSON_MOVED` (floor-plan coordinates) is MCT-only and needs the MCT overlay below. All
topics arrive on the same `corridorEvents` GraphQL subscription as the identification events.

## Multi-Camera Tracking (MCT)

Optional overlay (`mct/docker-compose.yml`) that tracks people **across** corridor cameras and
feeds the Hub's MCT-sourced zone notifications plus a live floor-plan visualizer.

**What it needs beyond the base stack:**

1. **A per-camera detection feed** from SmartFace Embedded Stream Processor cameras (MQTT,
   `edge-stream/<clientId>/frame_data`). The overlay taps an existing feed broker read-only via
   the `sfe-sp-mqtt-proxy` (client mode) — configure `MCT_SOURCE_*` in `.env.mct`. Plain RTSP
   demo cameras of the base stack do **not** produce this feed.
2. **A calibration model** of your cameras (homographies + floor plan), imported into the MCT
   Config API (`:8002`) under the name set as `MCT_MODEL`. Calibration is produced per site by
   Innovatrics.

**Bring-up** (after `start.sh`):

```bash
docker compose -p sceg-mct -f mct/docker-compose.yml --env-file .env.mct up -d
```

| Service        | URL                    | Purpose                                    |
| -------------- | ---------------------- | ------------------------------------------ |
| Visualizer     | http://localhost:8004  | live tracks on the floor plan              |
| Config API     | http://localhost:8002  | calibration models                         |
| Tracker API    | http://localhost:8420  | engine statistics (`/api/v1/sessions`)     |
| Proxy health   | http://localhost:18081 | feed-tap status (source/receiver counters) |
| Ingest broker  | http://localhost:15673 | MQTT-5 broker mgmt (guest/guest)           |

The track stream lands on the stack's shared RabbitMQ as protobuf
(`fanout://mct_tracker.tracking_updates/` + `fanout://position.message/`); the Hub consumes it
directly when `ZONE_MCT_ENABLED=true` (see `.env.hub`). Images are CI-pipeline builds mirrored
digest-1:1 to Harbor, pinned in `.env.mct`; they move to semver tags with the MCT release train.
