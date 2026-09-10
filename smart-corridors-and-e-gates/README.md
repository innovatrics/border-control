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

1. **A per-camera detection feed** from SmartFace Embedded Stream Processor cameras, delivered into
   the base stack's `rmq` over MQTT as `edge-stream/<clientId>/frame_data` — typically by an
   `sfe-sp-mqtt-proxy` at the camera site publishing into it. The tracker subscribes there directly,
   over plain MQTT 3.1.1. Plain RTSP demo cameras of the base stack do **not** produce this feed.
2. **A calibration model** of your cameras (homographies + floor plan), under the name set as
   `MCT_MODEL`. Calibration is produced per site by Innovatrics. Either drop the model directory it
   produced into `mct/models_data/` and run the `seed` profile below, or import it by hand with
   `POST /Models` plus a `PUT /Models/{model}/Cameras/{clientId}/CalibrationMap/projectionV2` per
   camera — full schema at http://localhost:8002/swagger. Without a model the tracker starts and
   stays up, but produces no tracks.

**Bring-up** (after `start.sh`). The first two commands are one-time setup:

```bash
# database schema — also after raising MCT_TAG
docker compose -p sceg-mct -f mct/docker-compose.yml --env-file .env.mct --profile migrate up -d

# load the calibration model from mct/models_data — skip if you import via Swagger instead
docker compose -p sceg-mct -f mct/docker-compose.yml --env-file .env.mct --profile seed up -d

# the overlay itself
docker compose -p sceg-mct -f mct/docker-compose.yml --env-file .env.mct up -d
```

Re-running the `seed` profile **overwrites** the model in the database, so leave it out of routine
restarts if you have recalibrated in place since.

MCT is a separate Compose project (`sceg-mct`), so `start.sh` never starts it and `stop.sh` /
`factory-reset.sh` never stop it. Tear it down explicitly:

```bash
docker compose -p sceg-mct -f mct/docker-compose.yml --env-file .env.mct down -v
```

| Service       | URL                   | Purpose                                 |
| ------------- | --------------------- | --------------------------------------- |
| Visualizer    | http://localhost:8004 | live tracks on the floor plan           |
| Config API    | http://localhost:8002 | calibration models                      |
| Tracker API   | http://localhost:8420 | engine statistics (`/api/v1/sessions`)  |
| Identifier    | http://localhost:8003 | joins tracks with SmartFace identities  |
| Recording     | http://localhost:8005 | pipeline recording log + snapshot export |

The track stream lands on the stack's shared RabbitMQ as protobuf
(`fanout://mct_tracker.tracking_updates/` + `fanout://position.message/`); the Hub consumes it
directly when `ZONE_MCT_ENABLED=true` (see `.env.hub`). Images are the released MCT suite mirrored
to Harbor, pinned by a single `MCT_TAG` in `.env.mct`.

**Is it tracking?** The visualizer is the quickest answer — dots moving on the floor plan. Per-frame
ingest lines in `docker logs mct-tracker` are DEBUG only, so at the default `INFO` level a healthy
tracker logs nothing per frame; set `MCT_LOG_LEVEL=DEBUG` if you need to see them. `:8005` records
the feeds and can export a snapshot when you need to show what the tracker was receiving.

The overlay publishes its ports on all interfaces and reuses the base stack's demo credentials
(`guest/guest`), so treat it as a lab/demo deployment — front it with a firewall before it sees an
untrusted network.

> **Earlier versions of this overlay** shipped a second RabbitMQ broker, a proxy that copied frames
> into it, and a watchdog that mounted the Docker socket to restart a tracker that occasionally
> wedged. None of the three is here any more. The tracker build of the time required MQTT 5, which
> RabbitMQ 3.12 cannot parse, so it needed a broker of its own; the released tracker speaks MQTT
> 3.1.1 and reads the stack's `rmq` directly. The wedge itself looks to have been a side effect of
> that extra broker — it ran RabbitMQ's default 30-minute `consumer_timeout`, whereas the stack's
> own `rmq` is configured for 6 hours. Six containers instead of eight, and nothing holding the
> Docker socket. If you are upgrading, remove the old project first:
> `docker compose -p sceg-mct -f mct/docker-compose.yml --env-file .env.mct down -v`.
