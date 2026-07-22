---
name: docker-shared-first
description: Check existing Docker patterns before writing new Dockerfiles or compose services. Use before creating containers, adding services, or modifying build contexts.
---

# Docker Shared-First

## Scope
Run before writing: Dockerfiles, docker-compose.yml services, .dockerignore entries, container build scripts.

## Methodology
1. INVENTORY: List all existing Dockerfiles and compose files in the project. Note patterns: base images, multi-stage builds, entrypoint conventions, health checks.
2. READ_EXISTING: Read the existing Dockerfiles. Understand build stages, cached layers, and runtime conventions.
3. CHECK_COMPOSE: Read the existing compose file. Understand service naming, network topology, volume mounts, env var passing.
4. EVALUATE: Can the new container reuse an existing pattern? Is there a standard base image already in use?

## Pattern Rules
- Build context: Determine repo root → use `-f path/to/Dockerfile` when Dockerfile is not at root
- Base images: Prefer the same base image family as existing services (consistency over novelty)
- Non-root: All containers run as non-root user. Follow the project's user convention (UID/GUID pattern)
- Health checks: Use the same health check pattern as existing services
- Logging: Log to stdout/stderr, not files. Let Docker's logging driver handle persistence

## Extraction Criteria
Extract a shared Docker pattern when ALL of these are true:
- SAME_BASE: The same base image or multi-stage build pattern is used in 2+ Dockerfiles
- NO_APP_SPECIFIC: The build stage or entrypoint pattern doesn't depend on application-specific paths
- CONSISTENT_LAYER: The layer caching strategy (dependency install → source copy) is the same

## Anti-Patterns
- DIFFERENT_BASE: Using `alpine` when all other services use `debian-slim`
- INCONSISTENT_USER: Running as `root` when all other services run as `nobody`/`1000`
- SKIP_MAP: Not reading the existing compose file before adding a new service
