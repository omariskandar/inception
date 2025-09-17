# **************************************************************************** #
#                                   Inception                                  #
# **************************************************************************** #

# Paths
SRC_DIR        := srcs
COMPOSE_FILE   := docker-compose.yml
ENV_FILE       := $(SRC_DIR)/.env

# Compose command autodetect (v1 vs v2)
COMPOSE_CMD    := $(shell command -v docker-compose >/dev/null 2>&1 && echo docker-compose || echo docker compose)

# Read a few vars from .env (strip quotes/CR)
PROJECT_NAME   := $(shell sed -n 's/^COMPOSE_PROJECT_NAME=\(.*\)/\1/p' $(ENV_FILE) | tr -d '\r"')
DOMAIN_NAME    := $(shell sed -n 's/^DOMAIN_NAME=\(.*\)/\1/p'            $(ENV_FILE) | tr -d '\r"')
HOST_DB_PATH   := $(shell sed -n 's/^HOST_DB_PATH=\(.*\)/\1/p'            $(ENV_FILE) | tr -d '\r"')
HOST_WP_PATH   := $(shell sed -n 's/^HOST_WP_PATH=\(.*\)/\1/p'            $(ENV_FILE) | tr -d '\r"')

.DEFAULT_GOAL := help

# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #

define ensure_env
	@ if [ ! -f "$(ENV_FILE)" ]; then \
		echo "[ERROR] $(ENV_FILE) not found. Create it first."; \
		exit 1; \
	fi
endef

define ensure_dirs
	@ if [ -z "$(HOST_DB_PATH)" ] || [ -z "$(HOST_WP_PATH)" ]; then \
		echo "[ERROR] HOST_DB_PATH / HOST_WP_PATH not set in $(ENV_FILE)"; \
		exit 1; \
	fi
	@ mkdir -p "$(HOST_DB_PATH)" "$(HOST_WP_PATH)"
endef

# We keep secrets at repo root (./secrets) but Compose (run in srcs/) expects ./secrets.
# This symlink makes srcs/secrets -> ../secrets if it doesn't exist.
define ensure_secrets_link
	@ if [ ! -d "secrets" ] && [ -d "../secrets" ]; then \
		ln -s ../secrets secrets; \
	fi
	@ for f in secrets/db_password.txt secrets/db_root_password.txt secrets/wp_admin_password.txt secrets/wp_user_password.txt ; do \
		if [ ! -f "$(SRC_DIR)/$$f" ] && [ ! -f "$$f" ]; then \
			echo "[ERROR] Missing secret file: $$f (expected at ./secrets or $(SRC_DIR)/secrets)"; \
			exit 1; \
		fi ; \
	done
endef

# Wrapper to run compose from srcs/
define compose
	@ ( cd $(SRC_DIR) && $(COMPOSE_CMD) -f $(COMPOSE_FILE) $(1) )
endef

# --------------------------------------------------------------------------- #
# Core targets
# --------------------------------------------------------------------------- #

.PHONY: all
all: up  ## Alias for `up`

.PHONY: up
up: ## Build and start services (detached)
	$(call ensure_env)
	$(call ensure_dirs)
	@ ( cd $(SRC_DIR) && $(call ensure_secrets_link) )
	$(call compose, up -d --build)

.PHONY: down
down: ## Stop & remove services (keep bind-mounted data)
	$(call ensure_env)
	$(call compose, down --remove-orphans)

.PHONY: build
build: ## Build images only
	$(call ensure_env)
	@ ( cd $(SRC_DIR) && $(call ensure_secrets_link) )
	$(call compose, build)

.PHONY: start
start: ## Start existing containers
	$(call ensure_env)
	$(call compose, start)

.PHONY: stop
stop: ## Stop running containers
	$(call ensure_env)
	$(call compose, stop)

.PHONY: restart
restart: ## Restart all services
	$(call ensure_env)
	$(call compose, restart)

.PHONY: logs
logs: ## Tail logs (Ctrl-C to exit)
	$(call ensure_env)
	$(call compose, logs -f --tail=150)

.PHONY: ps
ps: ## Show service status
	$(call ensure_env)
	$(call compose, ps)

# --------------------------------------------------------------------------- #
# Cleanup
# --------------------------------------------------------------------------- #

.PHONY: clean
clean: ## Down + remove local images/volumes/networks (keeps bind-mounted data)
	$(call ensure_env)
	$(call compose, down -v --rmi local --remove-orphans || true)

.PHONY: fclean
fclean: clean ## clean + delete host data directories
	@ if [ -n "$(HOST_DB_PATH)" ] && [ -n "$(HOST_WP_PATH)" ]; then \
		echo "[WARN] Removing host bind paths: $(HOST_DB_PATH) $(HOST_WP_PATH)"; \
		rm -rf "$(HOST_DB_PATH)" "$(HOST_WP_PATH)"; \
	else \
		echo "[WARN] HOST_DB_PATH/HOST_WP_PATH not set; skipping bind path removal."; \
	fi

.PHONY: re
re: fclean up ## Full rebuild & start

# --------------------------------------------------------------------------- #
# Utilities
# --------------------------------------------------------------------------- #

.PHONY: create-dirs
create-dirs: ## Create bind directories from .env
	$(call ensure_env)
	$(call ensure_dirs)

.PHONY: hosts-hint
hosts-hint: ## Show the /etc/hosts line to add inside your VM
	$(call ensure_env)
	@ echo "Add to /etc/hosts (inside VM) if needed:"
	@ echo "127.0.0.1  $(DOMAIN_NAME)"

.PHONY: which-compose
which-compose: ## Show which compose binary is used
	@ echo "Using: $(COMPOSE_CMD)"

.PHONY: help
help: ## Show help
	@ printf "\n\033[1mInception - Make targets\033[0m\n\n"
	@ awk 'BEGIN{FS=":.*##"; printf "Usage: make \033[36m<TARGET>\033[0m\n\nTargets:\n"} \
	/^[a-zA-Z0-9_\-\.]+:.*?##/ { printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@ printf "\nProject: \033[1m$(PROJECT_NAME)\033[0m  Domain: \033[1m$(DOMAIN_NAME)\033[0m\n\n"
