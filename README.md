# docker-opencode

Containerized [OpenCode](https://github.com/anomalyco/opencode) development environment. Mounts a project directory as `/workspace` inside the container and runs as the host user (matching UID/GID) to avoid file permission issues.

## Prerequisites

- Docker + Docker Compose
- GNU Make

## Quick Start

```bash
make          # or: make shell
```

First run prompts for a workspace selection from `~/repo`. The choice is saved to `.workspace` and reused on subsequent runs.

## Commands

| Command | Description |
|---------|-------------|
| `make shell` | Open interactive shell as host user — **default** |
| `make root` | Open interactive shell as root |
| `make start` | Start container in background (prompts workspace if not saved) |
| `make stop` | Stop the running container |
| `make restart` | Full rebuild: stop → clean → build → start |
| `make build` | Build the Docker image |
| `make clean` | Remove container and clear saved workspace |
| `make status` | Show container status |
| `make logs` | Follow container logs |
| `make select-workspace` | Re-select workspace (list or `[0]` to enter a path manually) |
| `make exec <cmd>` | Run a command as host user: `make exec ls -al` |

## Workspace

The workspace directory is mounted at `/workspace`. Workspaces are selected from `~/repo` by default:

```bash
make shell WORKSPACE_ROOT=~/projects
make select-workspace WORKSPACE_ROOT=/mnt/data
```

Selection is saved to `.workspace`. Absolute paths entered manually are supported. To switch workspace, run `make select-workspace` (or `make clean` to fully reset).

## Persistent Config

`.config/` on the host is mounted to `/home/opencode` inside the container. OpenCode's local state (settings, history, auth tokens) persists there across container restarts. The directory is gitignored except for `.gitkeep`.

## Secrets

Create `.secret` with `KEY=value` pairs — lines starting with `#` are ignored. Values are injected as environment variables at container start (not baked into the image).

## How It Works

1. `make start` reads `.workspace`, mounts that directory to `/workspace`, and runs the container via `docker compose run -d`
2. The entrypoint (`entrypoint.sh`) runs as root and:
   - Creates a group matching `HOST_GID` and a group matching `DOCKER_GID` (for Docker socket access)
   - Creates or renames the existing `opencode` user to match `HOST_UID`/`HOST_GID`
   - Writes `~/.bashrc` with a custom prompt and common aliases
   - Hands off to `sleep infinity` running as the host user
3. `make shell` looks up the username by UID inside the container and opens `bash` as that user

`HOST_UID`, `HOST_GID`, and `DOCKER_GID` are detected automatically from the host at `make` invocation time.

## Image

Built on `ghcr.io/anomalyco/opencode:latest` (Alpine). Additional packages installed at build time.

The built image is tagged `dk6v/opencode:<SCRIPT_VERSION>` (set in `.env`).

## Network

The container joins the `docker-internal` bridge network (`172.30.0.0/16`). If that network already exists on the host it is reused (expect a harmless warning about `external: true`).
