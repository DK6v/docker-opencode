.ONESHELL:
SHELL = /bin/bash

.DEFAULT_GOAL := shell

export HOST_UID = $(shell id -u ${USER})
export HOST_GID = $(shell id -g ${USER})

export DOCKER_GID = $(shell stat -c '%g' /var/run/docker.sock 2>/dev/null || echo "${HOST_GID}")

# Extract secrets from .secret file (format: KEY=value, lines starting with # are ignored)
SECRET_ARGS = $(shell \
	if [ -f .secret ]; then \
		cat .secret | grep -v '^#' | grep -v '^$$' | while IFS='=' read -r key value; do \
			printf -- '-e %s=%q ' "$$key" "$$value"; \
		done; \
	fi \
)

CONTAINER_NAME = opencode
WORKSPACE_FILE = .workspace
WORKSPACE_ROOT = $(HOME)/repo

.PHONY: build start stop shell root logs clean restart status exec select-workspace wait-ready

# Build the Docker image
build:
	docker compose build --progress=plain

# Select workspace only
select-workspace:
	@echo "Available workspaces in $(WORKSPACE_ROOT):"; \
	echo ""; \
	echo "[0] -- enter path manually --"; \
	ls -d $(WORKSPACE_ROOT)/*/ 2>/dev/null | xargs -n 1 basename | awk '{printf "[%d] %s\n", NR, $$0}'; \
	echo ""; \
	read -p "Enter number: " choice; \
	if [ "$$choice" = "0" ]; then \
		read -p "Enter path: " selected; \
		selected="$${selected/#\~/$${HOME}}"; \
		if [ ! -d "$$selected" ]; then \
			echo "Error: path '$$selected' does not exist"; \
			exit 1; \
		fi; \
	else \
		selected=$$(ls -d $(WORKSPACE_ROOT)/*/ 2>/dev/null | xargs -n 1 basename | sed -n "$${choice}p"); \
		if [ -z "$$selected" ]; then \
			echo "Invalid selection"; \
			exit 1; \
		fi; \
	fi; \
	echo "$$selected" > $(WORKSPACE_FILE); \
	echo "Workspace saved: $$selected"

# Create and start container in background if it doesn't exist
start:
	@if [ ! -f $(WORKSPACE_FILE) ]; then \
		$(MAKE) --no-print-directory select-workspace || exit 1; \
	fi; \
	WORKSPACE_DIR=$$(cat $(WORKSPACE_FILE)); \
	case "$$WORKSPACE_DIR" in \
		/*) WORKSPACE_PATH="$$WORKSPACE_DIR" ;; \
		*)  WORKSPACE_PATH="$(WORKSPACE_ROOT)/$$WORKSPACE_DIR" ;; \
	esac; \
	if [ ! -d "$$WORKSPACE_PATH" ]; then \
		echo "Error: Workspace path $$WORKSPACE_PATH does not exist"; \
		exit 1; \
	fi; \
	if [ -z "$$(docker ps -q -f name=$(CONTAINER_NAME))" ]; then \
		if [ -n "$$(docker ps -aq -f status=exited -f name=$(CONTAINER_NAME))" ]; then \
			echo "Starting existing container..."; \
			docker start $(CONTAINER_NAME); \
		else \
			echo "Creating and starting new container with workspace: $$WORKSPACE_DIR"; \
			echo "Mounting $$WORKSPACE_PATH to /workspace"; \
			docker compose run -d --name $(CONTAINER_NAME) \
				-e HOST_UID=$(HOST_UID) \
				-e HOST_GID=$(HOST_GID) \
				-e DOCKER_GID=$(DOCKER_GID) \
				$(SECRET_ARGS) \
				-v $$WORKSPACE_PATH:/workspace \
				$$(docker compose config --services | head -1); \
		fi; \
		$(MAKE) --no-print-directory wait-ready; \
	else \
		echo "Container is already running"; \
	fi

# Wait until entrypoint has finished user setup (up to 15s)
wait-ready:
	@echo "Waiting for container to be ready..."; \
	echo "Done"
	# for i in $$(seq 1 30); do \
	# 	docker exec $(CONTAINER_NAME) id $(HOST_UID) > /dev/null 2>&1 && echo "Container ready." && exit 0; \
	# 	sleep 0.5; \
	# done; \
	# echo "Error: container not ready after 15s"; exit 1

# Stop the running container
stop:
	@if [ -n "$$(docker ps -q -f name=$(CONTAINER_NAME))" ]; then \
		echo "Stopping container..."; \
		docker stop $(CONTAINER_NAME); \
	else \
		echo "Container is not running"; \
	fi

# Open an interactive shell inside the container (auto-starts if needed)
shell:
	@$(MAKE) --no-print-directory start
	@USER=$$(docker exec $(CONTAINER_NAME) awk -F: -v uid=$(HOST_UID) '$$3==uid{print $$1;exit}' /etc/passwd 2>/dev/null)
	docker exec -it --user "$$USER" $(CONTAINER_NAME) bash -i

# Open a root shell inside the container (auto-starts if needed)
root:
	@$(MAKE) --no-print-directory start
	docker exec -it --user root $(CONTAINER_NAME) bash -i

# Follow container logs
logs:
	docker compose logs -f

# Remove container completely
clean:
	@if [ -n "$$(docker ps -aq -f name=$(CONTAINER_NAME))" ]; then \
		echo "Removing container..."; \
		docker rm -f $(CONTAINER_NAME); \
	else \
		echo "Container does not exist"; \
	fi
	@rm -f $(WORKSPACE_FILE)

# Rebuild and restart everything
restart: stop clean build start

# Show container status
status:
	@docker ps -f name=$(CONTAINER_NAME) --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" || echo "Container not found"

# Execute arbitrary command inside the container
# Usage: make exec npm install
exec:
	@$(MAKE) --no-print-directory start
	@USER=$$(docker exec $(CONTAINER_NAME) awk -F: -v uid=$(HOST_UID) '$$3==uid{print $$1;exit}' /etc/passwd 2>/dev/null)
	docker exec -it --user "$$USER" $(CONTAINER_NAME) $(filter-out $@,$(MAKECMDGOALS))

%:
	@:
