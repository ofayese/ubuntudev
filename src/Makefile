# Makefile for Docker Pull Essentials
# Version: 1.0.0
# Last updated: 2025-06-11

.PHONY: help pull validate clean install check-deps dry-run parallel-pull quick-pull

# Default target
help:
	@echo "Docker Pull Essentials - Available targets:"
	@echo ""
	@echo "  pull          - Pull all essential Docker images"
	@echo "  quick-pull    - Pull only core images (fast)"
	@echo "  parallel-pull - Pull with maximum parallel workers"
	@echo "  dry-run       - Show what would be pulled"
	@echo "  validate      - Validate pulled images work correctly"
	@echo "  install       - Install scripts and set permissions"
	@echo "  check-deps    - Check prerequisites"
	@echo "  clean         - Clean up log files and temp data"
	@echo "  shellcheck    - Run shellcheck on all scripts"
	@echo ""
	@echo "Environment variables:"
	@echo "  PARALLEL      - Number of parallel workers (default: 4)"
	@echo "  TIMEOUT       - Timeout per image in seconds (default: 300)"
	@echo "  SKIP_AI       - Skip AI/ML models (true/false)"
	@echo ""
	@echo "Examples:"
	@echo "  make pull"
	@echo "  make PARALLEL=8 parallel-pull"
	@echo "  make SKIP_AI=true pull"

# Check prerequisites
check-deps:
	@echo "Checking prerequisites..."
	@command -v docker >/dev/null 2>&1 || (echo "ERROR: Docker not found" && exit 1)
	@docker info >/dev/null 2>&1 || (echo "ERROR: Docker daemon not accessible" && exit 1)
	@echo "✓ Docker is available and running"
	@command -v bash >/dev/null 2>&1 || (echo "ERROR: Bash not found" && exit 1)
	@echo "✓ Bash is available"
	@echo "Prerequisites check passed!"

# Install scripts and set permissions
install:
	@echo "Installing Docker Pull Essentials..."
	chmod +x docker-pull-essentials.sh
	chmod +x validate-docker-images.sh
	@echo "✓ Scripts are now executable"
	@echo "Installation completed!"

# Show what would be pulled (dry run)
dry-run: check-deps
	@echo "Running dry-run to show what would be pulled..."
	./docker-pull-essentials.sh --dry-run

# Pull all essential images
pull: check-deps install
	@echo "Pulling all essential Docker images..."
	./docker-pull-essentials.sh \
		$(if $(PARALLEL),--parallel $(PARALLEL),) \
		$(if $(TIMEOUT),--timeout $(TIMEOUT),) \
		$(if $(filter true,$(SKIP_AI)),--skip-ai,) \
		$(if $(filter true,$(SKIP_WINDOWS)),--skip-windows,)

# Quick pull (core images only)
quick-pull: check-deps install
	@echo "Quick pull - core images only..."
	./docker-pull-essentials.sh --skip-ai --parallel 2

# Parallel pull with maximum workers
parallel-pull: check-deps install
	@echo "Pulling with maximum parallel workers..."
	./docker-pull-essentials.sh --parallel 8

# Validate pulled images
validate: check-deps
	@echo "Validating pulled Docker images..."
	@test -f validate-docker-images.sh && chmod +x validate-docker-images.sh || echo "Warning: validate-docker-images.sh not found"
	./validate-docker-images.sh

# Clean up logs and temporary files
clean:
	@echo "Cleaning up logs and temporary files..."
	@rm -f docker-pull.log docker-validation.log
	@docker system prune -f >/dev/null 2>&1 || true
	@echo "✓ Cleanup completed"

# Run shellcheck on all scripts
shellcheck:
	@echo "Running shellcheck on bash scripts..."
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck docker-pull-essentials.sh validate-docker-images.sh || \
		echo "Warning: Some shellcheck issues found"; \
	else \
		echo "Warning: shellcheck not installed"; \
	fi

# Full workflow: pull, validate, and clean
full: pull validate
	@echo "Full workflow completed: pull + validate"

# Development targets
dev-install:
	@echo "Installing development dependencies..."
	@command -v shellcheck >/dev/null 2>&1 || echo "Consider installing shellcheck for linting"
	@echo "Development setup completed"

# Show disk usage
disk-usage:
	@echo "Docker disk usage:"
	@docker system df 2>/dev/null || echo "Unable to get Docker disk usage"

# Show version information
version:
	@echo "Docker Pull Essentials v1.1.0"
	@echo "Docker version:"
	@docker --version 2>/dev/null || echo "Docker not available"
	@echo "Bash version:"
	@bash --version | head -1 2>/dev/null || echo "Bash not available"

# Emergency cleanup (removes all Docker data)
emergency-clean:
	@echo "WARNING: This will remove ALL Docker data!"
	@read -p "Are you sure? (type 'yes' to confirm): " confirm && \
	if [ "$$confirm" = "yes" ]; then \
		docker system prune -a -f --volumes; \
		echo "Emergency cleanup completed"; \
	else \
		echo "Aborted"; \
	fi

# Show running containers
status:
	@echo "Docker system status:"
	@docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" 2>/dev/null || echo "No containers running"

# Network test
network-test:
	@echo "Testing network connectivity..."
	@docker run --rm alpine ping -c 1 docker.io >/dev/null 2>&1 && \
		echo "✓ Network connectivity OK" || \
		echo "✗ Network connectivity failed"
