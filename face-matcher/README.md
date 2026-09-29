# Face Matcher

Face Matcher is a real-time face identification server. It processes video streams, matches faces against watchlists and publishes the results over REST, GraphQL and RabbitMQ. Station is the web UI for watchlists, cameras, live previews and 1:N search.

# Deployment

1. Install `Docker` and `docker compose` on the host machine.
2. Login to container registry `docker login registry.dot.innovatrics.com -u <username> -p <password>`. The credentials are available in our [Customer Portal](https://customerportal.innovatrics.com/).
3. Identify hardware id (hwid) for your machine with command `docker run --rm registry.dot.innovatrics.com/vpp/license-manager:3.2.7`.
4. Obtain license for your hwid from our Customer Portal https://customerportal.innovatrics.com/
5. Copy the license file `iengine.lic` to `secrets/`.
6. Run `run.sh`.

Station is at http://localhost:8000.

## Scripts

- `run.sh` - starts dependencies, migrates the database, starts the platform services and Station
- `stop.sh` - stops everything, keeps data
- `factory-reset.sh` - stops everything and deletes containers, images and volumes

## Endpoints

| Service        | URL                           | Credentials                |
| -------------- | ----------------------------- | -------------------------- |
| Station        | http://localhost:8000         |                            |
| REST API       | http://localhost:8098         |                            |
| GraphQL API    | http://localhost:8097/graphql |                            |
| RabbitMQ       | http://localhost:15672        | guest / guest              |
| SeaweedFS (S3) | http://localhost:8333         | admin / admin              |
| pgAdmin        | http://localhost:7070         | admin@admin.com / Test1234 |

Ports are published on all interfaces with default credentials. Do not expose the host to an untrusted network.

## Configuration

- `.env` - all settings, documented inline. Section 4 is Station: image version, port, `STATION_IDENTIFICATION`.
- `.env.station` - Station settings
- `branding/station/` - Station logo, favicon and naming
- `docker-compose.yml`, `dependencies/docker-compose.yml`, `run.sh` - the Innovatrics video processing platform release package (`video_processing_deployment.zip`)
- `docker-compose.override.yml` - Station, the restart policy and `user: root`, see the comment inside

Not deployed: offline video processing, grouping, palm biometrics, Milvus, Access Controller.

## Changes to the release package

- `docker-compose.yml`, `.env` - `grouping`, `video-*` and `palm-*` services and their settings removed
- `.env` - `REGISTRY` points to Harbor; `Notifications__IncludeTemplates=true`; `Milvus__*` removed; section 4 added
- `dependencies/docker-compose.yml` - Milvus removed; RabbitMQ pinned to 4.3.6 with `queue_master_locator` permitted; one SeaweedFS data mount
- `run.sh` - license from `secrets/`, `STATION_PUBLIC_HOST` and the endpoint summary added; Milvus wait removed
- `deployment-common.sh` - Milvus wait removed
- `sync-embeddings-to-vector-db.sh`, `migrate-palms.sh`, `finalize-non-migrated-palms.sh` - deleted
- `docker-compose.override.yml`, `stop.sh`, `factory-reset.sh`, `.env.station`, `branding/` - added

## Upgrade

1. Mirror the new release images into `registry.dot.innovatrics.com/vpp/`.
2. Unpack the new `video_processing_deployment.zip` over this directory and re-apply the changes above.
3. If the face template model changed, run the migration below.
4. Run `run.sh`.

## Face templates migration

1. To start migration of face templates, execute
```
./migrate-faces.sh
```

This will stop the current compose services, spawn the required face detector and extractor services, and run the migration CLI command. After this, you should see output regarding the success rate of migration and also a list of watchlist members for which template migration was not possible. You should store this output to handle those members' faces manually by requesting reenrollment of their faces.

> **Note (1):** You can override the default template model version (`53`) by setting `FACE_MODEL_VERSION` env variable before running the script. Possible values are `52` (`fast`), `53` (`balanced`), `54` (`accurate`), `55` (`accurate_server`).

> **Note (2):** It is possible that there were some transient errors while running this script (e.g. some RPC calls may timeout). In that case, it is safe to run this command again.

2. To finalize migration, execute
```
./finalize-non-migrated-faces.sh
```
This will force the remaining faces that were not possible to migrate to be set to error state and thus be skipped by our matchers at startup.

3. Start the services again with `run.sh`.

## Watchlist update-log stream

If the release notes say the watchlist update-log stream needs regenerating, execute
```
./populate-wl-update-log-stream.sh
```

## Integration

A stack built on Face Matcher may rely on the following. Everything else is internal.

| Network      | `face-matcher-network`, created by `run.sh`. Join it with `external: true`.                        |
| ------------ | ------------------------------------------------------------------------------------------------- |
| REST API     | `api:8080`                                                                                        |
| GraphQL API  | `graphql-api:8080`. Face templates are included in notifications.                                  |
| RabbitMQ     | `rmq:5672` AMQP, `rmq:1883` MQTT, `rmq:5552` streams                                              |
| S3           | `seaweedfs:8333`. Use your own bucket.                                                             |
| PostgreSQL   | `pgsql:5432`                                                                                      |
| Station      | `fm-station:8000`                                                                                 |
| Admin image  | `${REGISTRY}admin:${VERSION}` from `.env`                                                          |
| Start order  | Face Matcher first. `run.sh` reads `STATION_IDENTIFICATION` and `STATION_PUBLIC_HOST` from the environment. |

Credentials are in `.env`.

## Production use

This deployment demonstrates the configuration needed to wire everything up. Change the credentials and restrict the published ports before production use.
