# **************************************************************************** #
#                                   Inception                                  #
# **************************************************************************** #

# Tools
COMPOSE        := docker compose
COMPOSE_FILE   := srcs/docker-compose.yml
ENV_FILE       := srcs/.env

# Derived vars from .env (kept simple & POSIX-y)
PROJECT_NAME   := $(shell awk -F= '/^COMPOSE_PROJECT_NAME=/{print $$2}' $(ENV_FILE))
DOMAIN_NAME    := $(shell awk -F= '/^DOMAIN_NAME=/{print $$2}'         $(ENV_FILE))
HOST_DB_PATH   := $(shell awk -F= '/^HOST_DB_PATH=/{print $$2}'         $(ENV_FILE))
HOST_WP_PATH   := $(shell awk -F= '/^HOST_WP_PATH=/{print $$2}'         $(ENV_FILE))

# Default target
.DEFAULT_GOAL := help

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

define ensure_env
	@ if [ ! -f "$(ENV_FILE)" ]; then \
		echo "[ERROR] $(ENV_FILE) not found. Create it first."; \
		exit 1; \
	fi
endef

define ensure_dirs
	@ mkdir -p "$(HOST_DB_PATH)" "$(HOST_WP_PATH)"
endef

define ensure_secrets
	@ for f in secrets/db_password.txt secrets/db_root_password.txt secrets/wp_admin_password.txt secrets/wp_user_password.txt ; do \
		if [ ! -f "$$f" ]; then \
			echo "[ERROR] Missing secret file: $$f"; \
			exit 1; \
		fi ; \
	done
endef

# -----------------------------------------------------------------------------
# Core targets
# -----------------------------------------------------------------------------

.PHONY: up
up: ## Build and start all services (detached)
	$(call ensure_env)
	$(call ensure_secrets)
	$(call ensure_dirs)
	@ $(COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) up -d --build

.PHONY: down
down: ## Stop and remove services (keep bind-mounted data)
	$(call ensure_env)
	@ $(COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) down --remove-orphans

.PHONY: build
build: ## Build images only
	$(call ensure_env)
	$(call ensure_secrets)
	@ $(COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) build

.PHONY: start
start: ## Start existing containers
	$(call ensure_env)
	@ $(COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) start

.PHONY: stop
stop: ## Stop running containers
	$(call ensure_env)
	@ $(COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) stop

.PHONY: restart
restart: ## Restart all services
	$(call ensure_env)
	@ $(COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) restart

.PHONY: logs
logs: ## Tail logs (Ctrl-C to exit)
	$(call ensure_env)
	@ $(COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) logs -f --tail=150

.PHONY: ps
ps: ## Show service status
	$(call ensure_env)
	@ $(COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) ps

# -----------------------------------------------------------------------------
# Cleanup targets
# -----------------------------------------------------------------------------

.PHONY: clean
clean: ## Down + remove local images/volumes/networks (keeps bind-mounted data in /home/<login>/data)
	$(call ensure_env)
	@ $(COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) down -v --rmi local --remove-orphans || true

.PHONY: fclean
fclean: clean ## clean + delete host data directories
	@ echo "[WARN] Removing host bind paths: $(HOST_DB_PATH) $(HOST_WP_PATH)"
	@ rm -rf "$(HOST_DB_PATH)" "$(HOST_WP_PATH)"

.PHONY: re
re: fclean up ## Full rebuild & start

# -----------------------------------------------------------------------------
# Utilities
# -----------------------------------------------------------------------------

.PHONY: create-dirs
create-dirs: ## Create host bind directories from .env
	$(call ensure_env)
	$(call ensure_dirs)

.PHONY: hosts-hint
hosts-hint: ## Show the /etc/hosts line you likely need on your VM
	$(call ensure_env)
	@ echo "Add this to /etc/hosts (inside your VM) if not already present:"
	@ echo "127.0.0.1  $(DOMAIN_NAME)"

.PHONY: help
help: ## Show this help
	@ printf "\n\033[1mInception - Make targets\033[0m\n\n"
	@ awk 'BEGIN{FS=":.*##"; printf "Usage: make \033[36m<TARGET>\033[0m\n\nTargets:\n"} \
	/^[a-zA-Z0-9_\-\.]+:.*?##/ { printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@ printf "\nProject: \033[1m$(PROJECT_NAME)\033[0m  Domain: \033[1m$(DOMAIN_NAME)\033[0m\n\n"
