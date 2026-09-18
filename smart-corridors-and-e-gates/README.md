# Smart Corridors & e-Gates

Corridor and e-gate clearance on top of [Face Matcher](../face-matcher/): the Hub turns the identification stream into per-traveller clearance decisions, CIGS groups the detections of one traveller into a single identity, and the operational display is the officer-facing dashboard.

Face Matcher is a required part of this module, not an option. `start.sh` brings it up first, so you do not deploy it separately.

## Quick start

1. Clone this repository onto the target machine or server.
2. Obtain a license from the [Innovatrics Customer Portal](https://customerportal.innovatrics.com) — see [License](#license) below.
3. Place `iengine.lic` into [`../secrets/`](../secrets/).
4. From the `smart-corridors-and-e-gates/` folder, run:

```bash
bash start.sh
```

## Prerequisites

- Docker Engine 25 or newer with Docker Compose v2.24 or newer.
- Access to the Innovatrics Harbor registry `registry.dot.innovatrics.com` — see [Registry login](../face-matcher/README.md#registry-login).

## License

One `iengine.lic` at [`../secrets/`](../secrets/) licenses both modules. For corridors it must carry two things:

- the **iengine** block, used by the Face Matcher platform and by CIGS (hardware-bound);
- a **`smart_corridor`** block, used by the Hub (`smart_corridor.hub`) and the operational display (`smart_corridor.operational_display`). Without it those two are fail-closed and refuse to serve.

Request a license with the `smart_corridor` block enabled from the Customer Portal. Getting your hardware ID and the file's permissions are covered in the [Face Matcher README](../face-matcher/README.md#license).

## Scripts

```bash
bash start.sh          # start Face Matcher and the corridor services
bash stop.sh           # stop both, keep data (MCT is managed separately)
bash factory-reset.sh  # stop + wipe all containers, images and volumes of both modules
```

## Endpoints

The corridor services, plus the Face Matcher endpoints underneath them:

| Service            | URL                                          | Credentials                |
| ------------------ | -------------------------------------------- | -------------------------- |
| Corridor dashboard | http://localhost:8095                        | —                          |
| Hub GraphQL        | http://localhost:8090/corridor-hub/graphql   | —                          |
| Hub GraphiQL       | http://localhost:8090/corridor-hub/graphiql  | —                          |
| CIGS health        | http://localhost:8096/actuator/health        | —                          |
| Platform REST API  | http://localhost:8098                        | —                          |
| Platform GraphQL   | http://localhost:8097/graphql                | —                          |
| Station            | http://localhost:8000                        | —                          |
| RabbitMQ           | http://localhost:15672                       | guest / guest              |
| SeaweedFS (S3 API) | http://localhost:8333                        | admin / admin              |
| pgAdmin            | http://localhost:7070                        | admin@admin.com / Test1234 |

## Configuration

### `.env` — corridor service versions

| Variable           | Description                                |
| ------------------ | ------------------------------------------ |
| `REGISTRY`         | Registry prefix for the corridor images    |
| `CIGS_VERSION`     | Corridor Identity Grouping Service version |
| `HUB_VERSION`      | Smart Corridors & e-Gates Hub version      |
| `FRONTEND_VERSION` | Frontend image tag                         |
| `FRONTEND_PORT`    | Dashboard port (default `8095`)            |

The platform version and the Station version live in the Face Matcher module: `../face-matcher/platform/.env` and `../face-matcher/.env`.

### Station

Station comes from the Face Matcher module and keeps the Face Matcher brand here: it is the Face Matcher operator UI wherever it runs. The one thing `start.sh` changes is `STATION_IDENTIFICATION=false`, which leaves Station's 1:N Identification page off, because the corridor dashboard is the operator surface in this deployment.

### `.env.hub` — Hub wiring

| Group      | Key variables                                                                                                                 |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Source     | `VPP_GRAPHQL_HOST` / `VPP_GRAPHQL_PORT` — the platform GraphQL API (`graphql-api:8080` inside the Compose network)            |
| Watchlists | `VPP_ADAPTER_ALLOWED_WATCHLISTS` — watchlist IDs that grant GREEN clearance (comma-separated)                                  |
| Units      | `HUB_UNITS_0_*` — corridor/e-gate unit definitions with their camera IDs (empty/unset or `*` ⇒ the unit processes all cameras) |
| Storage    | `STORAGE_S3_BUCKET`, `STORAGE_S3_ACCESS_KEY`, `STORAGE_S3_SECRET_KEY`                                                          |

Face crop thumbnails stream through the Hub's in-service image proxy (`/corridor-hub/images`) — the browser fetches crops through the Hub, never directly from the S3 storage, so no host-networking setup is required. `STORAGE_S3_*` only configures the Hub's server-side access to the platform's SeaweedFS (in-network `seaweedfs:8333`); `start.sh` creates the `corridor-hub` bucket there.

### Zone notifications (Hub ≥ 0.4.0)

The Hub can derive `zone.*` notifications (person entered / left / moved, occupancy, counts,
avoiding-identification) with a **per-topic source switch** — each topic is computed from platform
tracklets, CIGS identities, or the MCT track stream. `.env.hub` ships a commented example block;
`ZONE_PERSON_MOVED` (floor-plan coordinates) is MCT-only and needs the MCT overlay below. All
topics arrive on the same `corridorEvents` GraphQL subscription as the identification events.

## Multi-Camera Tracking (MCT)

Optional overlay (`mct/docker-compose.yml`) that tracks people **across** corridor cameras and
feeds the Hub's MCT-sourced zone notifications plus a live floor-plan visualizer. The released MCT
images target `linux/amd64`; ARM hosts need Docker x86-64 emulation. `start.sh` does not start
MCT, and the base stack needs no calibration data.

**What it needs beyond the base stack:**

1. **A per-camera detection feed** from SmartFace Embedded Stream Processor cameras, delivered into
   the base stack's `rmq` over MQTT as `edge-stream/<clientId>/frame_data` — typically by an
   `sfe-sp-mqtt-proxy` at the camera site publishing into it. The tracker subscribes there directly,
   over plain MQTT 3.1.1. Plain RTSP demo cameras of the base stack do **not** produce this feed.
2. **A calibration model** of your cameras (homographies + floor plan), under the name set as
   `MCT_MODEL`. Calibration is produced per site by Innovatrics. Either drop the model directory it
   produced into `mct/models_data/` and run the `seed` profile below, or import it by hand with
   `POST /Models` plus a `PUT /Models/{model}/Cameras/{clientId}/CalibrationMap/projectionV2` per
   camera — full schema at http://localhost:8002/openapi/v1.json (interactive UI:
   http://localhost:8002/swagger/index.html?url=/openapi/v1.json). The tracker and visualizer fail
   to start until the model exists. For manual import, first start `configurationApi` after migration.

**Bring-up** (after `start.sh`). The first two commands are one-time setup and wait for completion:

```bash
# database schema — also after raising MCT_TAG
docker compose -p sceg-mct -f mct/docker-compose.yml --env-file mct/.env.mct --profile migrate run --rm dbMigrator

# load the calibration model from mct/models_data — skip if you import via Swagger instead
docker compose -p sceg-mct -f mct/docker-compose.yml --env-file mct/.env.mct --profile seed run --rm configApiSeeder

# the overlay itself
docker compose -p sceg-mct -f mct/docker-compose.yml --env-file mct/.env.mct up -d
```

Re-running the `seed` profile **overwrites** the model in the database, so leave it out of routine
restarts if you have recalibrated in place since.

MCT is a separate Compose project (`sceg-mct`), so `start.sh` never starts it and `stop.sh` /
`factory-reset.sh` never stop it. Stop it explicitly (retaining calibration and recordings):

```bash
docker compose -p sceg-mct -f mct/docker-compose.yml --env-file mct/.env.mct down
```

Add `-v` only for a factory reset: it deletes the calibration database, recordings and snapshots.

| Service       | URL                   | Purpose                                 |
| ------------- | --------------------- | --------------------------------------- |
| Visualizer    | http://localhost:8004 | live tracks on the floor plan           |
| Config API    | http://localhost:8002 | calibration models                      |
| Tracker API   | http://localhost:8420 | engine statistics (`/api/v1/sessions`)  |
| Identifier    | http://localhost:8003 | joins tracks with the platform identities |
| Recording     | http://localhost:8005 | pipeline recording log + snapshot export |

The track stream lands on the stack's shared RabbitMQ as protobuf
(`fanout://mct_tracker.tracking_updates/` + `fanout://position.message/`); the Hub consumes it
directly when `ZONE_MCT_ENABLED=true` (see `.env.hub`). Images are the released MCT suite mirrored
to Harbor, pinned by a single `MCT_TAG` in `mct/.env.mct`.

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
> the former RabbitMQ 3.12 base broker could not parse. The current base stack uses RabbitMQ 4;
> the released tracker speaks MQTT 3.1.1 and reads that shared `rmq` directly on `fm-network`.
> The wedge itself looks to have been a side effect of that extra broker — it ran RabbitMQ's default 30-minute `consumer_timeout`, whereas the stack's
> own `rmq` is configured for 6 hours. Six containers instead of eight, and nothing holding the
> Docker socket. If you are upgrading, back up the calibration and recordings, then remove
> the old containers first:
> `docker compose -p sceg-mct -f mct/docker-compose.yml --env-file mct/.env.mct down --remove-orphans`.

## Upgrading from the pre-Face-Matcher layout

Earlier versions of this repository kept the platform in `smart-corridors-and-e-gates/vpp/`, Station in this module's Compose file and the license in `smart-corridors-and-e-gates/secrets/`. All three moved. Nothing is lost: the Compose project names (`vpp`, `vpp-dependencies`) and therefore the database, RabbitMQ and SeaweedFS volumes are unchanged.

`start.sh` handles the two things that would otherwise break on the first run after the upgrade: it moves your `iengine.lic` up to `../secrets/`, and it removes the `sf-station` container the old project left behind so the Face Matcher module can recreate it.

Two leftovers are harmless and yours to clear when convenient. `smart-corridors-and-e-gates/vpp/` stays on disk holding only the old license symlink. The Docker network is now `fm-network`, so the empty `vpp-network` stays behind until you run `docker network rm vpp-network`.
