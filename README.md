# Smart Corridor

Corridor and e-gate clearance on top of [Face Matcher](face-matcher/). The Hub turns identifications into per-traveller clearance decisions, CIGS groups detections into identities, and the operational display is the officer dashboard. Face Matcher is vendored in `face-matcher/` and started by `start.sh`.

# Deployment

1. Install `Docker` and `docker compose` on the host machine.
2. Login to container registry `docker login registry.dot.innovatrics.com -u <username> -p <password>`. The credentials are available in our [Customer Portal](https://customerportal.innovatrics.com/).
3. Identify hardware id (hwid) for your machine with command `docker run --rm registry.dot.innovatrics.com/vpp/license-manager:3.2.7`.
4. Obtain a license with the `smart_corridor` block for your hwid from our Customer Portal https://customerportal.innovatrics.com/
5. Copy the license file `iengine.lic` to `secrets/`.
6. Run `start.sh`.

The dashboard is at http://localhost:8095.

## Scripts

- `start.sh` - starts Face Matcher, then the corridor services
- `stop.sh` - stops everything, keeps data
- `factory-reset.sh` - stops everything and deletes containers, images and volumes

MCT is not started or stopped by these scripts. See below.

## Endpoints

| Service            | URL                                         | Credentials                |
| ------------------ | ------------------------------------------- | -------------------------- |
| Corridor dashboard | http://localhost:8095                       |                            |
| Hub GraphQL        | http://localhost:8090/corridor-hub/graphql  |                            |
| Hub GraphiQL       | http://localhost:8090/corridor-hub/graphiql |                            |
| CIGS health        | http://localhost:8096/actuator/health       |                            |
| Station            | http://localhost:8000                       |                            |
| REST API           | http://localhost:8098                       |                            |
| GraphQL API        | http://localhost:8097/graphql               |                            |
| RabbitMQ           | http://localhost:15672                      | guest / guest              |
| SeaweedFS (S3)     | http://localhost:8333                       | admin / admin              |
| pgAdmin            | http://localhost:7070                       | admin@admin.com / Test1234 |

Ports are published on all interfaces with default credentials. Do not expose the host to an untrusted network.

## Configuration

- `.env` - corridor image versions and the dashboard port
- `.env.hub` - Hub: allowed watchlists, corridor units and their cameras, storage, zone notifications. Documented inline.
- `face-matcher/` - a copy of the Face Matcher repository. Do not edit it. To upgrade, replace the directory with a checkout of the new release. `start.sh` runs it with `STATION_IDENTIFICATION=false`.

All services join `face-matcher-network`, created by Face Matcher. The corridor services use only what [`face-matcher/README.md`](face-matcher/README.md#integration) lists.

## Zone notifications (Hub 0.4.0 and newer)

The Hub can emit `zone.*` notifications (person entered, left, moved, occupancy, counts) on the `corridorEvents` subscription, each computed from the platform, CIGS or MCT. `.env.hub` contains a commented example. `person_moved` requires MCT.

# Multi-Camera Tracking (MCT)

Optional. Tracks people across corridor cameras and feeds MCT-based zone notifications and a floor-plan visualizer. Images are `linux/amd64`. Configuration is in `mct/.env.mct`.

Requires:

1. A per-camera detection feed from SmartFace Embedded Stream Processor cameras, published to `rmq` over MQTT as `edge-stream/<clientId>/frame_data`. RTSP cameras do not produce this feed.
2. A calibration model, produced per site by Innovatrics, in `mct/models_data/`, named as `MCT_MODEL`. Alternatively import it through http://localhost:8002/swagger/index.html?url=/openapi/v1.json after starting `configurationApi`.

Start, after `start.sh`:

```
docker compose -p sceg-mct -f mct/docker-compose.yml --env-file mct/.env.mct --profile migrate run --rm dbMigrator
docker compose -p sceg-mct -f mct/docker-compose.yml --env-file mct/.env.mct --profile seed run --rm configApiSeeder
docker compose -p sceg-mct -f mct/docker-compose.yml --env-file mct/.env.mct up -d
```

Run the first two only once, and `migrate` again after raising `MCT_TAG`. `seed` overwrites the model in the database.

Stop:

```
docker compose -p sceg-mct -f mct/docker-compose.yml --env-file mct/.env.mct down
```

Add `-v` to also delete the calibration database, recordings and snapshots.

| Service     | URL                   |
| ----------- | --------------------- |
| Visualizer  | http://localhost:8004 |
| Config API  | http://localhost:8002 |
| Tracker API | http://localhost:8420 |
| Identifier  | http://localhost:8003 |
| Recording   | http://localhost:8005 |

Set `ZONE_MCT_ENABLED=true` in `.env.hub` for the Hub to consume the track stream. Set `MCT_LOG_LEVEL=DEBUG` in `mct/.env.mct` to log every ingested frame.

## Production use

This deployment demonstrates the configuration needed to wire everything up. Change the credentials and restrict the published ports before production use.
