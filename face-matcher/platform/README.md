# Face Matcher platform

The engine half of the Face Matcher module: the Innovatrics video processing platform release package, trimmed to the face-identification services. It is vendored as shipped apart from the edits listed in [`../README.md`](../README.md#platform--the-platform).

- `docker-compose.yml` — the platform services
- `docker-compose.override.yml` — the local additions (restart policy, `user: root`); Compose merges it automatically
- `.env` — the configuration shared by all services, documented inline; edit this to configure the platform
- `dependencies/docker-compose.yml` — the bundled dependencies (database, RabbitMQ, S3 storage)
- `run.sh` — brings the platform up (dependencies, database migration, S3 bucket, services)
- the template-migration and watchlist-stream helper scripts described below

**Do not run `run.sh` directly for a normal start.** Use `bash start.sh` in the module folder above: it places the license where `run.sh` expects it, then brings Station up as well. `run.sh` is the platform-only step that `start.sh` calls. Once running, the services can be restarted at any time with `docker compose up -d` from this folder.

## Template migration

When upgrading from an older version, stored face templates may need migrating to the template model bundled with the new version. Read the release notes first: if the model did not change, skip this.

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

3. Start the services again with `bash ../start.sh`.

Palm template migration is not part of Face Matcher; the palm services and their migration scripts have been removed.

## Regenerating the watchlist update-log stream

If the release notes say the watchlist update stream log needs regenerating, you can rebuild that stream from the watchlist data currently in the SQL database:

```
./populate-wl-update-log-stream.sh
```
