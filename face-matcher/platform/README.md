# Face Matcher platform

The Innovatrics video processing platform release package (`video_processing_deployment.zip`), trimmed to the face identification services. It is started by `../start.sh`; do not run `run.sh` directly.

- `docker-compose.yml` - platform services
- `docker-compose.override.yml` - restart policy and `user: root`, see the comment inside
- `.env` - configuration, documented inline
- `dependencies/docker-compose.yml` - PostgreSQL, RabbitMQ, SeaweedFS
- `run.sh` - starts dependencies, migrates the database, creates the S3 bucket, starts the services

## Changes to the release package

- `docker-compose.yml`, `.env` - `grouping`, `video-*` and `palm-*` services and their settings removed
- `.env` - `REGISTRY` points to Harbor; `Notifications__IncludeTemplates=true`; `Milvus__*` removed
- `dependencies/docker-compose.yml` - Milvus removed; RabbitMQ pinned to 4.3.6 with `queue_master_locator` permitted; one SeaweedFS data mount
- `run.sh`, `deployment-common.sh` - Milvus wait removed
- `sync-embeddings-to-vector-db.sh`, `migrate-palms.sh`, `finalize-non-migrated-palms.sh` - deleted
- `docker-compose.override.yml` - added

## Upgrade

1. Mirror the new release images into `registry.dot.innovatrics.com/border-control/vpp/`.
2. Unpack the new `video_processing_deployment.zip` over this directory and re-apply the changes above.
3. If the face template model changed, run the migration below.
4. Run `../start.sh`.

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

3. Start the services again with `../start.sh`.

## Watchlist update-log stream

If the release notes say the watchlist update-log stream needs regenerating, execute
```
./populate-wl-update-log-stream.sh
```
