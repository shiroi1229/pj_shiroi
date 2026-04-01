# CLAUDE.md

This file provides guidance for AI assistants working in this repository.

## Project Overview

This is a full-stack AI-powered web application skeleton. The infrastructure is defined via Docker Compose. The application code directories (`frontend/`, `backend/`, `sd-api/`) are not yet implemented — this is a greenfield project.

## Architecture

```
pj_shiroi/
├── docker-compose.yaml     # Infrastructure definition (only tracked file so far)
├── frontend/               # Node.js 18 + Yarn frontend (to be created)
├── backend/                # Python FastAPI backend (to be created)
├── sd-api/                 # Stable Diffusion image generation service (to be created)
└── qdrant_storage/         # Qdrant vector DB storage (auto-created by Docker)
```

### Services

| Service         | Technology                             | Port  | Role                              |
|----------------|----------------------------------------|-------|-----------------------------------|
| frontend        | Node.js 18 / Yarn                      | 3000  | Web UI                            |
| backend         | Python FastAPI (uvicorn-gunicorn)      | 8000  | REST API                          |
| db              | PostgreSQL 14                          | 5432  | Persistent relational storage     |
| redis           | Redis 7.2                              | 6379  | Caching / sessions / task queue   |
| qdrant          | Qdrant (latest)                        | 6333  | Vector search / semantic search   |
| image-generator | Custom Dockerfile in `./sd-api`        | 5000  | Stable Diffusion image generation |

### Service Dependencies

```
frontend → backend → db, redis, qdrant
image-generator → redis, qdrant
```

## Development Workflow

### Starting the stack

```bash
docker compose up
```

### Starting individual services

```bash
docker compose up backend db redis qdrant
```

### Rebuilding after code changes

```bash
docker compose up --build
```

### Stopping

```bash
docker compose down
```

### Stopping and removing volumes (destructive)

```bash
docker compose down -v
```

## Environment Variables

Current values are hardcoded in docker-compose.yaml for local development. For production, use a `.env` file:

| Variable       | Default value                              | Used by  |
|---------------|--------------------------------------------|----------|
| DATABASE_URL   | postgresql://user:password@db:5432/mydb   | backend  |
| POSTGRES_USER  | user                                       | db       |
| POSTGRES_PASSWORD | password                               | db       |
| POSTGRES_DB    | mydb                                       | db       |

## Frontend Conventions (to be established)

- Runtime: Node.js 18
- Package manager: **Yarn** (use `yarn`, not `npm`)
- Dev server runs via `yarn dev` on port 3000
- Source lives in `./frontend/`, mounted into `/app` in the container

## Backend Conventions (to be established)

- Language: Python 3.9
- Framework: **FastAPI**
- Server: uvicorn/gunicorn (via `tiangolo/uvicorn-gunicorn-fastapi` image)
- Main app module should be at `backend/app/main.py` (FastAPI convention for this image)
- Exposed on port 8000 (mapped from container port 80)

## Image Generation Service

- Lives in `./sd-api/`
- Requires a `Dockerfile` at `./sd-api/Dockerfile`
- Exposed on port 5000
- Depends on Redis (likely for task queuing) and Qdrant (likely for image embeddings)

## Qdrant (Vector Database)

- REST API: `http://localhost:6333`
- gRPC: `localhost:6334`
- Storage persisted to `./qdrant_storage/`

## Git Conventions

- Primary branch: `main`
- Feature branches follow: `claude/<description>-<id>` pattern
- There is only one commit so far; the project is in its initial state

## Key Implementation Notes for AI Assistants

1. **No application code exists yet.** When asked to implement features, create the appropriate directory structure first.
2. **Use Yarn, not npm** for frontend package management.
3. **FastAPI entrypoint** for the `tiangolo/uvicorn-gunicorn-fastapi` image must be at `/app/app/main.py` with an `app` variable.
4. **Database credentials** in docker-compose.yaml are for local dev only — never commit real secrets.
5. **sd-api** needs its own `Dockerfile` — it is built locally, unlike the other services which pull images.
6. **Qdrant** is likely used for AI feature search (image similarity, semantic search) — coordinate usage between backend and image-generator services.
