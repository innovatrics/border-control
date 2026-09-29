# Face Matcher

Face Matcher is a real-time face identification server. It processes video streams, matches faces against watchlists and publishes the results over REST, GraphQL and RabbitMQ. Station is the web UI for watchlists, cameras, live previews and 1:N search.

# Deployment

1. Install `Docker` and `docker compose` on the host machine.
2. Login to container registry `docker login registry.dot.innovatrics.com -u <username> -p <password>`. The credentials are available in our [Customer Portal](https://customerportal.innovatrics.com/).
3. Identify hardware id (hwid) for your machine with command `docker run --rm registry.dot.innovatrics.com/border-control/vpp/license-manager:3.2.7`.
4. Obtain license for your hwid from our Customer Portal https://customerportal.innovatrics.com/
5. Copy the license file `iengine.lic` to `secrets/`.
6. Run `start.sh`.

Station is at http://localhost:8000.

## Scripts

- `start.sh` - starts the platform (dependencies, database migration, services) and Station
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

- `.env` - Station image version and port; `STATION_IDENTIFICATION` enables the 1:N Identification page (default `true`)
- `.env.station` - Station settings
- `branding/station/` - Station logo, favicon and naming
- `platform/` - the video processing platform. Settings are documented inline in `platform/.env`. See [`platform/README.md`](platform/README.md) for the changes to the release package, upgrades and template migration.

Not deployed: offline video processing, grouping, palm biometrics, Milvus, Access Controller.

## Integration

A stack built on Face Matcher may rely on the following. Everything else is internal.

| Network      | `face-matcher-network`, created by `platform/run.sh`. Join it with `external: true`.               |
| ------------ | ------------------------------------------------------------------------------------------------- |
| REST API     | `api:8080`                                                                                        |
| GraphQL API  | `graphql-api:8080`. Face templates are included in notifications.                                  |
| RabbitMQ     | `rmq:5672` AMQP, `rmq:1883` MQTT, `rmq:5552` streams                                              |
| S3           | `seaweedfs:8333`. Use your own bucket.                                                             |
| PostgreSQL   | `pgsql:5432`                                                                                      |
| Station      | `fm-station:8000`                                                                                 |
| Admin image  | `${REGISTRY}admin:${VERSION}` from `platform/.env`                                                 |
| Start order  | Face Matcher first. `start.sh` reads `STATION_IDENTIFICATION` and `STATION_PUBLIC_HOST` from the environment. |

Credentials are in `platform/.env`.

## Production use

This deployment demonstrates the configuration needed to wire everything up. Change the credentials and restrict the published ports before production use.
