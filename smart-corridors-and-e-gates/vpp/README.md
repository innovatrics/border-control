# Video processing platform (VPP) deployment

This archive contains everything needed to run a VPP deployment with Docker Compose:

- `docker-compose.yml` — the VPP services for this deployment
- `.env` — the configuration shared by all services (edit this to configure the deployment)
- `dependencies/docker-compose.yml` — the bundled dependencies (database, RabbitMQ, S3 storage, vector database)
- `run.sh` — brings the whole deployment up (dependencies, database migration, S3 bucket, services)
- the template-migration and embedding-sync helper scripts described below

## Deployment

1. Install `Docker` and `docker compose` on the host machine.
2. Log in to the container registry: `docker login <registry> -u <username> -p <password>`. The credentials are available in our [Customer Portal](https://customerportal.innovatrics.com/).
3. Identify the hardware id (hwid) of your machine and obtain a license for it from the Customer Portal.
4. Copy the license file `iengine.lic` into the root of this directory (next to `docker-compose.yml`). Create the file before the first run — if it is missing, Docker creates an empty directory in its place.
5. Run `./run.sh`. The script starts the dependencies, migrates the database to this version, creates the S3 bucket and starts the VPP services. Its comments explain each step.

Once running, the services can be restarted at any time with `docker compose up -d`.

## Template migration

When upgrading from an older version, stored face/palm templates may need migrating to the template model bundled with this version.

### Face templates

1. Start the migration:
   ```
   ./migrate-faces.sh
   ```
   This stops the running services, spawns temporary face detector/extractor workers and runs the migration. It then prints the success rate and the watchlist members whose templates could not be migrated. Store that output so you can re-enroll those members' faces manually.

   > **Note (1):** Override the template model version (default `53`) with the `FACE_MODEL_VERSION` env variable. Values: `52` (fast), `53` (balanced), `54` (accurate), `55` (accurate_server).

   > **Note (2):** Transient errors (e.g. RPC timeouts) can happen. It is safe to run the script again.

2. Finalize the migration:
   ```
   ./finalize-non-migrated-faces.sh
   ```
   This forces the faces that could not be migrated into the error state so the matchers skip them at startup.

3. Start the services again:
   ```
   docker compose up -d
   ```

### Palm templates

1. Start the migration:
   ```
   ./migrate-palms.sh
   ```
   This stops the running services, spawns temporary palm detector/extractor workers and runs the migration, then reports which members' palms could not be migrated.

   > **Note:** Transient errors can happen. It is safe to run the script again.

2. Finalize the migration:
   ```
   ./finalize-non-migrated-palms.sh
   ```

3. Start the services again:
   ```
   docker compose up -d
   ```

## Syncing embeddings to the vector database

VPP can optionally store face and palm embeddings in a vector database (Milvus) for matching. To sync the embeddings currently stored in the SQL database into the vector database:
   ```
   ./sync-embeddings-to-vector-db.sh
   ```

## Regenerating the watchlist update-log stream

 If release notes contains information that watchlist update stream log needs to be regenerated. You can rebuild that stream from the watchlist data currently in the SQL database:

```
./populate-wl-update-log-stream.sh
```