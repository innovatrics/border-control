# Face Matcher

Real-time face identification. Face Matcher watches camera streams, detects and tracks faces, extracts biometric templates and matches them against your watchlists, then publishes the results over REST, GraphQL and a message broker. Station, the bundled web UI, is where operators manage watchlists, cameras and live previews, and where they run a 1:N search of a single photo against the enrolled population.

Face Matcher is the base module of this repository. It runs on its own, and [Smart Corridors & e-Gates](../smart-corridors-and-e-gates/) builds on it.

## Quick start

1. Clone this repository onto the target machine or server.
2. Obtain a license from the [Innovatrics Customer Portal](https://customerportal.innovatrics.com) — see [License](#license) below.
3. Place `iengine.lic` into [`../secrets/`](../secrets/).
4. From the `face-matcher/` folder, run:

```bash
bash start.sh
```

Station comes up on http://localhost:8000.

## Prerequisites

- Docker Engine 25 or newer with Docker Compose v2.24 or newer (the platform relies on inline `configs` and health-check `start_interval`).
- Access to the Innovatrics Harbor registry `registry.dot.innovatrics.com` — see [Registry login](#registry-login).

## License

Face Matcher needs a single `iengine.lic` tied to the hardware of the machine it runs on. The same file licenses every service. Face Matcher itself only needs the file's **iengine/IFace** block; the `smart_corridor` block matters only if you also deploy Smart Corridors & e-Gates on top.

To get your hardware ID, run:

```bash
docker run --rm registry.dot.innovatrics.com/border-control/vpp/license-manager:3.2.7
```

Provide this ID when requesting a license from the [Customer Portal](https://customerportal.innovatrics.com), then place the file at `../secrets/iengine.lic` before running `start.sh`.

The license must be readable by the user the containers run as (`chmod 644`); `start.sh` applies this automatically. A license the containers cannot read shows up as `No license file was found` in the platform logs. The platform services deliberately run as root (see [the platform section](#platform--the-platform)); without that, the engine rejects the license with `License has different HWID than this machine`.

## Registry login

Innovatrics images are served from Harbor. Infrastructure images are pulled from Docker Hub. Before the first run:

```bash
docker login registry.dot.innovatrics.com -u USER_NAME -p PASSWORD
```

The registry USER_NAME and PASSWORD are provided separately by Innovatrics.

## Scripts

```bash
bash start.sh          # start the platform (dependencies, DB migration, services) and Station
bash stop.sh           # stop everything, keep all data
bash factory-reset.sh  # stop + wipe containers, images and volumes (deletes watchlists and crops)
```

## Endpoints

| Service            | URL                             | Credentials                |
| ------------------ | ------------------------------- | -------------------------- |
| Station            | http://localhost:8000           | —                          |
| REST API           | http://localhost:8098           | —                          |
| GraphQL API        | http://localhost:8097/graphql   | —                          |
| DB sync leader     | http://localhost:8100           | —                          |
| RabbitMQ           | http://localhost:15672          | guest / guest              |
| SeaweedFS (S3 API) | http://localhost:8333           | admin / admin              |
| pgAdmin            | http://localhost:7070           | admin@admin.com / Test1234 |

These are demo credentials on ports published to all interfaces. Put the deployment behind a firewall before it sees an untrusted network.

## What Face Matcher does not include

Face Matcher is a deliberately narrowed deployment of the Innovatrics video processing platform. These parts of the platform are **not** deployed, and their configuration has been removed from `platform/.env`:

| Removed | Services | Why |
| ------- | -------- | --- |
| Offline video processing | `video-reader`, `video-collector`, `video-aggregator` | Face Matcher identifies live streams. Processing recorded video files is out of scope. |
| Grouping | `grouping` | Unused. Smart Corridors does its own identity grouping in CIGS. |
| Palm biometrics | `palm-detector`, `palm-extractor` | Face Matcher is faces only. The palm template-migration scripts are gone with them. |
| Access Controller | — | Not supported. It was never deployed here; `ACCESS_CONTROLLER_ADDRESS` stays empty in `.env.station`. |
| Vector database | `milvus` and friends | Not used; `VectorDB__Provider=none`. Removed before this module existed. |

Pedestrian detection, generic object detection, edge-stream processing and database synchronisation are still deployed. They are candidates for a later trim, not decided yet.

## Configuration

### `.env` — the module

| Variable                 | Description                                                                       |
| ------------------------ | --------------------------------------------------------------------------------- |
| `REGISTRY`               | Registry prefix for the Station image                                              |
| `STATION_VERSION`        | Station image tag                                                                  |
| `STATION_PORT`           | Station host port (default `8000`)                                                 |
| `STATION_IDENTIFICATION` | Station's 1:N Identification page (default `true`)                                 |

### `.env.station` — Station

Station's own settings: the platform API addresses (`api:8080`, `graphql-api:8080`), the S3 storage, watchlist member labels, face validation limits and the optional Auth0/Keycloak wiring. `start.sh` sets `STATION_PUBLIC_HOST` to `$(hostname)` so the browser can open presigned crop URLs; override it before running `start.sh` if the machine is reached under a different name.

### `branding/station/` — brand assets

Station inlines `logo-product.svg`, `logo-product-without-text.svg`, `favicon-product.ico` and `naming-product.json` at startup. The logo and favicon here are typographic placeholders carrying the product name; swap them for the final brand assets without touching the deployment.

Station wears the Face Matcher brand in every deployment, including one running underneath Smart Corridors & e-Gates. Station is the Face Matcher operator UI, so it says so wherever it runs.

### `platform/` — the platform

`platform/` is the Innovatrics video processing platform release package (`video_processing_deployment.zip`), vendored as shipped except for the edits below. All of its settings are documented inline in `platform/.env`; `VERSION` there is the deployed version. See [`platform/README.md`](platform/README.md) for its own helper scripts (template migration after an upgrade, watchlist stream regeneration).

| File                              | Edit                                                                                           | Why                                                                                 |
| --------------------------------- | ---------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `docker-compose.yml`              | `grouping`, the three video services and the two palm services removed                         | See [What Face Matcher does not include](#what-face-matcher-does-not-include)        |
| `.env`                            | the configuration blocks of those services removed                                             | Same                                                                                  |
| `.env`                            | `REGISTRY=registry.dot.innovatrics.com/border-control/vpp/` (release: internal registry)        | Customers pull everything from Harbor                                                 |
| `.env`                            | `Notifications__IncludeTemplates=true` (release: `false`)                                      | Clients consume face templates from the GraphQL notifications                          |
| `dependencies/docker-compose.yml` | `milvus`, `milvus-etcd` and `milvus-create-user` removed (and their volumes/configs)           | The vector database is not used (`VectorDB__Provider=none`)                            |
| `dependencies/docker-compose.yml` | One SeaweedFS data mount; pin RabbitMQ 4.3.6 and permit legacy `queue_master_locator` arguments | Keep the blob storage on a single volume, and support Smart Corridors Hub 0.4 on RabbitMQ 4 |
| `run.sh`, `deployment-common.sh`  | the `ensure_milvus_user_provisioned` wait and the helper behind it removed                     | Follows the Milvus removal                                                             |
| `.env`, `docker-compose.yml`      | the `Milvus__*` connection settings removed; `VectorDB__Provider=none` stays                   | Nothing to connect to, and the release ships a placeholder password in them            |
| `sync-embeddings-to-vector-db.sh` | deleted                                                                                        | Needs Milvus                                                                           |
| `migrate-palms.sh`, `finalize-non-migrated-palms.sh` | deleted                                                     | Follow the palm removal                                                                |
| `docker-compose.override.yml`     | Added (not in the release): `restart: unless-stopped` on every service and `user: root` on the 17 that load a biometric engine or match templates (all but `graphql-api`, `streamdatadbworker`, `edge-streams-state-synchronizer` and the `db-synchronization-*` pair) | The release ships no restart policy; and as uid 10001 the licensing library cannot read the root-only hardware identifiers, so it derives a different HWID and rejects licenses issued for the HWID printed by `license-manager` (`License has different HWID than this machine`, confirmed by the platform team). Remove `user: root` once licensing works for uid 10001. |

Services reach each other by their Compose service names on the shared `fm-network` (`graphql-api`, `api`, `rmq`, `seaweedfs`, `pgsql`); the APIs listen on port `8080` inside the network.

#### Upgrading the platform

1. Mirror the new release's images (and `license-manager`) into `registry.dot.innovatrics.com/border-control/vpp/`. This is done by Innovatrics with internal tooling; it is not part of this repository.
2. Unpack the new `video_processing_deployment.zip` over `platform/` (delete the old contents first) and re-apply the local edits listed above.
3. Read the release notes. If the face template model changed, run `platform/migrate-faces.sh` and `platform/finalize-non-migrated-faces.sh` as described in [`platform/README.md`](platform/README.md) before starting the services.
4. Run `bash start.sh` — the platform's `run.sh` migrates the database on the way up.

## Names still carrying the old product

The deployment is fully rebranded. The Compose projects are `face-matcher-platform`, `face-matcher-dependencies` and `face-matcher-station`, the network is `fm-network`, Station's container is `fm-station`, the database is `facematcher` and the blob bucket is `face-matcher`.

What is left belongs to the images themselves and changes when Innovatrics publishes rebranded ones:

- the image paths `registry.dot.innovatrics.com/border-control/vpp/…` and the Station image name `sf-station`;
- the engine's internal service identifiers `SFBase` and `SFCam1`–`SFCam5`, which the database migration seeds and the images match on;
- the environment variable names the corridor display and the Hub read, such as `SMARTFACE_GQL_URL` and `VPP_GRAPHQL_HOST`.
