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

The platform requires an `iengine.lic` file tied to the hardware of the machine it runs on.

To get your hardware ID, run:

```bash
docker run --rm registry.dot.innovatrics.com/border-control/vpp/license-manager:3.2.7
```

Provide this ID when requesting a license from the [Customer Portal](https://customerportal.innovatrics.com).

Once you have the file, place it at `./secrets/iengine.lic` before running `start.sh`.

The license file must be readable by the user the VPP containers run as (`chmod 644 secrets/iengine.lic`); `start.sh` applies this automatically. A license the containers cannot read shows up as `No license file was found` in the VPP logs.

## Registry login

All images — the Smart Corridors services and the VPP — are served from a single registry. Before the first run:

```bash
docker login registry.dot.innovatrics.com -u USER_NAME -p PASSWORD
```

The registry USER_NAME and PASSWORD is provided separately by Innovatrics.

## Scripts

```bash
bash start.sh          # start VPP (dependencies, DB migration, services) and the corridor services
bash stop.sh           # stop everything, keep data
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

SmartFace Station is the legacy SmartFace admin UI (watchlists, cameras, previews). The VPP release no longer ships it, so it is deployed from this stack for backward compatibility, pointed at the VPP APIs (`api:80`, `graphql-api:80`) and the VPP's SeaweedFS. The Access Controller is not deployed, so `ACCESS_CONTROLLER_ADDRESS` stays empty. `start.sh` sets `S3_PUBLIC_ENDPOINT` to `http://$(hostname):8333` so the browser can open presigned crop URLs; override `SFS_PUBLIC_HOST` before running `start.sh` if the machine is reached under a different name.

### `.env.hub` — Hub wiring

| Group      | Key variables                                                                                                                 |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------- |
| VPP source | `VPP_GRAPHQL_HOST` / `VPP_GRAPHQL_PORT` — the VPP GraphQL API (`graphql-api:80` inside the Compose network)                   |
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
| `run.sh`                          | `ensure_milvus_user_provisioned` wait removed                                                          | Follows the Milvus removal                                                 |
| `sync-embeddings-to-vector-db.sh` | deleted                                                                                                | Needs Milvus                                                               |

`VERSION` in `vpp/.env` is the deployed VPP version. It is pinned to `v5_4.41.0.9996` on purpose: it is the last release whose containers run as root. From `v5_4.41.1` the images run as uid 10001, and the licensing library then computes a hardware ID that differs from the one printed by `license-manager`, so licenses issued for the documented HWID are rejected at startup with `License has different HWID than this machine`. Do not bump `VERSION` until VPP ships a HWID tool that matches its services. All other VPP settings are documented inline in `vpp/.env`; see `vpp/README.md` for the VPP's own helper scripts (template migration after an upgrade, watchlist stream regeneration).

The VPP services are reachable from the corridor services by their Compose service names on the shared `vpp-network` (`graphql-api`, `api`, `rmq`, `seaweedfs`, `pgsql`); the APIs listen on port `80` inside the network.

#### Upgrading the VPP

1. Mirror the new release's images (and `license-manager`) into `registry.dot.innovatrics.com/border-control/vpp/`. This is done by Innovatrics with internal tooling; it is not part of this repository.
2. Unpack the new `video_processing_deployment.zip` over `vpp/` (delete the old contents first) and re-apply the local edits listed above.
3. Read the VPP release notes. If the face template model changed, run `vpp/migrate-faces.sh` and `vpp/finalize-non-migrated-faces.sh` as described in `vpp/README.md` before starting the services.
4. Run `bash start.sh` — the VPP `run.sh` migrates the database to the new version on the way up.
