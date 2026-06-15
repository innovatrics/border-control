# Smart Corridors and e-Gates — All-in-One Sample

Runnable Docker Compose sample for the **Smart Corridors and e-Gates** use case, built on top of [SmartFace](https://github.com/innovatrics/smartface).

This sample spins up the full SmartFace stack — face detection, recognition, access control, and the Station operator UI — ready to be extended with corridor-specific and e-gate-specific configuration.

## Prerequisites

| Requirement | Version |
|-------------|---------|
| Docker Engine | ≥ 20.10.10 |
| Docker Compose plugin | ≥ 2.x |
| Valid `iengine.lic` license | from [Customer Portal](https://customerportal.innovatrics.com) |

### Registry authentication

Pull access to `registry.gitlab.com/innovatrics/smartface/` requires credentials from the Customer Portal:

```bash
docker login registry.gitlab.com
```

### Hardware ID (for license request)

```bash
docker run --rm registry.gitlab.com/innovatrics/smartface/sf-base:<SF_VERSION> print-hardware-id
```

## Quick start

```bash
# 1. Place your license file here
cp /path/to/iengine.lic .

# 2. Start everything
chmod +x run.sh
./run.sh
```

Once up, the following endpoints are available:

| Service | URL | Credentials |
|---------|-----|-------------|
| SmartFace Station | http://localhost:8000 | — |
| REST API | http://localhost:8098 | — |
| GraphQL API | http://localhost:8097 | — |
| OData API | http://localhost:8099 | — |
| RabbitMQ management | http://localhost:15672 | guest / guest |
| MinIO console | http://localhost:9001 | minioadmin / minioadmin |
| pgAdmin | http://localhost:7070 | admin@admin.com / admin |

## Configuration

| File | Purpose |
|------|---------|
| `.env` | Main configuration (versions, DB, RMQ, S3, logging) |
| `.env.sfac` | Access Controller overrides (filters, debounce, MQTT) |
| `.env.sfstation` | SmartFace Station overrides (API URLs, features) |

Edit `.env` to change versions before first run:

```dotenv
SF_VERSION=v5_4.40.2
AC_VERSION=v5_1.14.0
SFS_VERSION=v5_1.32.0
```

### Database

PostgreSQL is used by default. To switch to MS SQL, uncomment the `mssql` block in `sf_dependencies/docker-compose.yml` and update `.env`:

```dotenv
Database__DbEngine=MsSql
ConnectionStrings__CoreDbContext=Server=mssql;Database=SmartFace;User ID=sa;Password=Test1234;TrustServerCertificate=true;
```

## Stopping

```bash
# Stop SmartFace services only
docker compose down

# Stop + remove infrastructure (destroys all data volumes)
docker compose -f sf_dependencies/docker-compose.yml down -v
```

## Structure

```
smart-corridors-and-e-gates/
├── docker-compose.yml          # SmartFace application services
├── .env                        # Main environment config
├── .env.sfac                   # Access Controller overrides
├── .env.sfstation              # Station overrides
├── run.sh                      # Bootstrap + start script
├── iengine.lic                 # License file (not committed)
└── sf_dependencies/
    ├── docker-compose.yml      # Infrastructure: pgsql, rmq, minio
    ├── docker-compose-common.yml
    └── etc_rmq/
        ├── enabled_plugins     # RabbitMQ plugin list
        └── rabbitmq.conf       # RabbitMQ configuration
```

## License

This sample is provided under the same terms as the [SmartFace](https://github.com/innovatrics/smartface) project. SmartFace itself requires a valid commercial license from [Innovatrics](https://www.innovatrics.com).
