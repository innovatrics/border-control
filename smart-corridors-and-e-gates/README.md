# Smart Corridors & e-Gates

Docker Compose stack for the Smart Corridors & e-Gates solution, built on top of the Innovatrics Video Processing Platform (VPP).

## Quick start

1. Clone this repository onto the target machine or server.
2. Obtain a license from [Innovatrics Customer Portal](https://customerportal.innovatrics.com) — see [License](#license) below.
3. Navigate to the `smart-corridors-and-e-gates/` folder.
4. Place `iengine.lic` into `./secrets/`.
5. Run:

```bash
bash start.sh
```

## Prerequisites

- Docker Engine 25 or newer with Docker Compose v2.24 or newer (the bundled VPP release relies on inline `configs` and health-check `start_interval`).
- Access to the Innovatrics Harbor registry `registry.dot.innovatrics.com` — see [Registry login](#registry-login).

## License

The stack requires a single `iengine.lic` file tied to the hardware of the machine it runs on. The
same file licenses every service: the SmartFace/VPP platform and CIGS use its iengine block, while the
Hub and the operational-display frontend additionally require a `smart_corridor` block — without it
those two services are fail-closed and refuse to serve. Request a license with the `smart_corridor`
block enabled from the Customer Portal.

To get your hardware ID, run:

```bash
docker run --rm registry.dot.innovatrics.com/border-control/vpp/license-manager:3.2.7
```

Provide this ID when requesting a license from the [Customer Portal](https://customerportal.innovatrics.com).

Once you have the file, place it at `./secrets/iengine.lic` before running `start.sh`.

The license file must be readable by the user the VPP containers run as (`chmod 644 secrets/iengine.lic`); `start.sh` applies this automatically. A license the containers cannot read shows up as `No license file was found` in the VPP logs. Note that the VPP services are deliberately run as root (see the `vpp/` section below); without that, VPP v5_4.41.1 and newer reject the license with `License has different HWID than this machine`.

## Registry login

Innovatrics application images (corridor services, VPP and MCT) are served from Harbor.
Infrastructure images and the autoheal helper are pulled from Docker Hub. Before the first run:

```bash
docker login registry.dot.innovatrics.com -u USER_NAME -p PASSWORD
```

The registry USER_NAME and PASSWORD is provided separately by Innovatrics.

## Scripts

```bash
bash start.sh          # start VPP (dependencies, DB migration, services) and the corridor services
bash stop.sh           # stop the base stack, keep data (MCT is managed separately)
bash factory-reset.sh  # stop + wipe all containers, images, and volumes
```

## Endpoints

| Service            | URL                                          | Credentials                |
| ------------------ | -------------------------------------------- | -------------------------- |
| Corridor dashboard | http://localhost:8095                        | —                          |
| Hub GraphQL        | http://localhost:8090/corridor-hub/graphql   | —                          |
| Hub GraphiQL       | http://localhost:8090/corridor-hub/graphiql  | —                          |
| CIGS health        | http://localhost:8096/actuator/health        | —                          |
| VPP REST API       | http://localhost:8098                        | —                          |
| VPP GraphQL API    | http://localhost:8097/graphql                | —                          |
| SF Station         | http://localhost:8000                        | —                          |
| RabbitMQ           | http://localhost:15672                       | guest / guest              |
| SeaweedFS (S3 API) | http://localhost:8333                        | admin / admin              |
| pgAdmin            | http://localhost:7070                        | admin@admin.com / Test1234 |

## Configuration

### `.env` — service versions

| Variable           | Description                                |
| ------------------ | ------------------------------------------ |
| `REGISTRY`         | Registry prefix for the corridor images    |
| `CIGS_VERSION`     | Corridor Identity Grouping Service version |
| `HUB_VERSION`      | Smart Corridors & e-Gates Hub version      |
| `FRONTEND_VERSION` | Frontend image tag                         |
| `FRONTEND_PORT`    | Dashboard port (default `8095`)            |
| `SFS_VERSION`      | SmartFace Station image tag                |

### `.env.sfstation` — SmartFace Station

SmartFace Station is the legacy SmartFace admin UI (watchlists, cameras, previews). The VPP release no longer ships it, so it is deployed from this stack for backward compatibility, pointed at the VPP APIs (`api:8080`, `graphql-api:8080`) and the VPP's SeaweedFS. The Access Controller is not deployed, so `ACCESS_CONTROLLER_ADDRESS` stays empty. `start.sh` sets `S3_PUBLIC_ENDPOINT` to `http://$(hostname):8333` so the browser can open presigned crop URLs; override `SFS_PUBLIC_HOST` before running `start.sh` if the machine is reached under a different name.

### `.env.hub` — Hub wiring

| Group      | Key variables                                                                                                                 |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------- |
| VPP source | `VPP_GRAPHQL_HOST` / `VPP_GRAPHQL_PORT` — the VPP GraphQL API (`graphql-api:8080` inside the Compose network)                 |
| Watchlists | `VPP_ADAPTER_ALLOWED_WATCHLISTS` — watchlist IDs that grant GREEN clearance (comma-separated)                                  |
| Units      | `HUB_UNITS_0_*` — corridor/e-gate unit definitions with their camera IDs (empty/unset or `*` ⇒ the unit processes all cameras) |
| Storage    | `STORAGE_S3_BUCKET`, `STORAGE_S3_ACCESS_KEY`, `STORAGE_S3_SECRET_KEY`                                                          |

Face crop thumbnails stream through the Hub's in-service image proxy (`/corridor-hub/images`) — the browser fetches crops through the Hub, never directly from the S3 storage, so no host-networking setup is required. `STORAGE_S3_*` only configures the Hub's server-side access to the VPP's SeaweedFS (in-network `seaweedfs:8333`); `start.sh` creates the `corridor-hub` bucket there.

### `vpp/` — Video Processing Platform

`vpp/` is the VPP release deployment package (`video_processing_deployment.zip`), vendored as shipped except for these local edits:

| File                              | Edit                                                                                                   | Why                                                                        |
| --------------------------------- | ------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------- |
| `.env`                            | `REGISTRY=registry.dot.innovatrics.com/border-control/vpp/` (release: internal registry)              | Customers pull everything from Harbor                                      |
| `.env`                            | `Notifications__IncludeTemplates=true` (release: `false`)                                              | The Hub and CIGS consume face templates from the VPP GraphQL notifications |
| `dependencies/docker-compose.yml` | `milvus`, `milvus-etcd` and `milvus-create-user` services (and their volumes/configs) removed          | The vector database is not used (`VectorDB__Provider=none`)                |
| `dependencies/docker-compose.yml` | One SeaweedFS data mount; pin RabbitMQ 4.3.6 and permit legacy `queue_master_locator` arguments | Preserve the existing data volume and support Hub 0.4 on RabbitMQ 4 |
| `run.sh`                          | `ensure_milvus_user_provisioned` wait removed                                                          | Follows the Milvus removal                                                 |
| `sync-embeddings-to-vector-db.sh` | deleted                                                                                                | Needs Milvus                                                               |
| `docker-compose.override.yml`     | Added (not in the release): `container_name` (the SmartFace service names: `SFCam1`, `SFApi`, …) and `restart: unless-stopped` on every service, plus `user: root` on the 21 that load a biometric engine or match templates (all but `graphql-api`, `streamdatadbworker`, `video-reader`, `video-collector`, `edge-streams-state-synchronizer`, `db-synchronization-*`) | Compose would otherwise name the containers `vpp-cam-1-1`, so `docker ps` would not line up with the `OS service name` shown in SF Station; the release ships no restart policy; and as uid 10001 the licensing library cannot read the root-only hardware identifiers, so it derives a different HWID and rejects licenses issued for the HWID printed by `license-manager` (`License has different HWID than this machine`, confirmed by the VPP team). Remove `user: root` once VPP licensing works for uid 10001. |

`VERSION` in `vpp/.env` is the deployed VPP version. All other VPP settings are documented inline in `vpp/.env`; see `vpp/README.md` for the VPP's own helper scripts (template migration after an upgrade, watchlist stream regeneration).

The VPP services are reachable from the corridor services by their Compose service names on the shared `vpp-network` (`graphql-api`, `api`, `rmq`, `seaweedfs`, `pgsql`); the APIs listen on port `8080` inside the network.

#### Upgrading the VPP

1. Mirror the new release's images (and `license-manager`) into `registry.dot.innovatrics.com/border-control/vpp/`. This is done by Innovatrics with internal tooling; it is not part of this repository.
2. Unpack the new `video_processing_deployment.zip` over `vpp/` (delete the old contents first) and re-apply the local edits listed above.
3. Read the VPP release notes. If the face template model changed, run `vpp/migrate-faces.sh` and `vpp/finalize-non-migrated-faces.sh` as described in `vpp/README.md` before starting the services.
4. Run `bash start.sh` — the VPP `run.sh` migrates the database to the new version on the way up.

### Zone notifications (Hub ≥ 0.4.0)

The Hub can derive `zone.*` notifications (person entered / left / moved, occupancy, counts,
avoiding-identification) with a **per-topic source switch** — each topic is computed from VPP
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
docker compose -p sceg-mct -f mct/docker-compose.yml --env-file .env.mct --profile migrate run --rm dbMigrator

# load the calibration model from mct/models_data — skip if you import via Swagger instead
docker compose -p sceg-mct -f mct/docker-compose.yml --env-file .env.mct --profile seed run --rm configApiSeeder

# the overlay itself
docker compose -p sceg-mct -f mct/docker-compose.yml --env-file .env.mct up -d
```

Re-running the `seed` profile **overwrites** the model in the database, so leave it out of routine
restarts if you have recalibrated in place since.

MCT is a separate Compose project (`sceg-mct`), so `start.sh` never starts it and `stop.sh` /
`factory-reset.sh` never stop it. Stop it explicitly (retaining calibration and recordings):

```bash
docker compose -p sceg-mct -f mct/docker-compose.yml --env-file .env.mct down
```

Add `-v` only for a factory reset: it deletes the calibration database, recordings and snapshots.

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
> the former RabbitMQ 3.12 base broker could not parse. The current base stack uses RabbitMQ 4;
> the released tracker speaks MQTT 3.1.1 and reads that shared `rmq` directly on `vpp-network`.
> The wedge itself looks to have been a side effect of that extra broker — it ran RabbitMQ's default 30-minute `consumer_timeout`, whereas the stack's
> own `rmq` is configured for 6 hours. Six containers instead of eight, and nothing holding the
> Docker socket. If you are upgrading, back up the calibration and recordings, then remove
> the old containers first:
> `docker compose -p sceg-mct -f mct/docker-compose.yml --env-file .env.mct down --remove-orphans`.
