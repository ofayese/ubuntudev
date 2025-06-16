#!/usr/bin/env bash
# docker-pull-supervisor.sh
# Fully self-contained Docker Image Puller with:
# - Parallelism
# - Disk checks
# - Resume
# - Progress bar
# - WSL2 auto-detection
# - Volume management

set -euo pipefail

### CONFIGURATION
# Default Parameters
RETRIES=2
TIMEOUT=300
MIN_FREE_DISK_GB=20
LOG_FILE="docker-pull-supervisor.log"
# shellcheck disable=SC2034
STATE_FILE="docker-pull-state.txt"
DRY_RUN=false
SKIP_AI=false
SKIP_WINDOWS=false
RESUME=false
DEBUG=false

# Parse CLI args
while [[ $# -gt 0 ]]; do
    case "$1" in
    --retry)
        RETRIES="$2"
        shift 2
        ;;
    --timeout)
        TIMEOUT="$2"
        shift 2
        ;;
    --skip-ai)
        SKIP_AI=true
        shift
        ;;
    --skip-windows)
        SKIP_WINDOWS=true
        shift
        ;;
    --dry-run)
        DRY_RUN=true
        shift
        ;;
    --debug)
        DEBUG=true
        shift
        ;;
    --resume)
        RESUME=true
        shift
        ;;
    --log-file)
        LOG_FILE="$2"
        shift 2
        ;;
    --help | -h)
        echo "Usage: $0 [--retry N] [--timeout SEC] [--dry-run] [--debug] [--skip-ai] [--skip-windows] [--resume]"
        echo "Note: Sequential processing (workers removed for simplicity)"
        exit 0
        ;;
    *)
        echo "Unknown argument: $1"
        exit 1
        ;;
    esac
done

# WSL2 detection (info only now)
if grep -qEi "(Microsoft|WSL)" /proc/version &>/dev/null; then
    echo "Detected WSL2 environment"
fi

# Disk space check
AVAILABLE_DISK=$(df --output=avail -BG / | tail -1 | tr -dc '0-9')
if ((AVAILABLE_DISK < MIN_FREE_DISK_GB)); then
    echo "ERROR: Only ${AVAILABLE_DISK}GB free — minimum required: ${MIN_FREE_DISK_GB}GB."
    exit 1
fi

# Optional volume cleanup (can be commented out if you want)
echo "Docker volume usage before pull:"
docker system df -v
echo "Pruning dangling volumes..."
docker volume prune -f || true
echo "Docker volume usage after prune:"
docker system df -v
# Image definitions
IMAGES=(
    # base_os
    "IMAGE:ubuntu:22.04:Ubuntu-22.04"
    "IMAGE:debian:12-slim:Debian-12-Slim"
    "IMAGE:alpine:3.19:Alpine-3.19"
    # programming_languages
    "IMAGE:python:3.12-slim:Python-3.12-Slim"
    "IMAGE:node:20-alpine:Node-20-Alpine"
    "IMAGE:openjdk:21-jdk-slim:OpenJDK-21-Slim"
    "IMAGE:golang:1.22-alpine:Go-1.22-Alpine"
    "IMAGE:ruby:3.3-slim:Ruby-3.3-Slim"
    "IMAGE:php:8.3-cli-alpine:PHP-8.3-CLI-Alpine"
    # databases
    "IMAGE:postgres:16-alpine:PostgreSQL-16-Alpine"
    "IMAGE:mysql:8.0:MySQL-8.0"
    "IMAGE:mariadb:11.2:MariaDB-11.2"
    "IMAGE:mongo:7.0:MongoDB-7.0"
    "IMAGE:redis:7.2-alpine:Redis-7.2-Alpine"
    "IMAGE:redis/redis-stack:7.2.0-v0:Redis-Stack-7.2"
    "IMAGE:pgvector/pgvector:pg16:PostgreSQL-Vector-16"
    "IMAGE:clickhouse/clickhouse-server:24.3-alpine:ClickHouse-24.3"
    # devcontainers
    "IMAGE:mcr.microsoft.com/devcontainers/universal:2-linux:DevContainer-Universal-Linux"
    "IMAGE:mcr.microsoft.com/devcontainers/base:ubuntu-24.04:DevContainer-Base-Ubuntu"
    "IMAGE:mcr.microsoft.com/devcontainers/python:3-bullseye:DevContainer-Python-Bullseye"
    "IMAGE:mcr.microsoft.com/devcontainers/javascript-node:20-bullseye:DevContainer-Node-Bullseye"
    # microsoft_dotnet
    "IMAGE:mcr.microsoft.com/dotnet/sdk:9.0:Dotnet-SDK-9.0"
    "IMAGE:mcr.microsoft.com/dotnet/aspnet:9.0:Dotnet-ASP.NET-9.0"
    "IMAGE:mcr.microsoft.com/dotnet/runtime:9.0:Dotnet-Runtime-9.0"
    "IMAGE:mcr.microsoft.com/dotnet/framework/aspnet:4.8.1:Dotnet-Framework-ASP.NET-4.8.1"
    "IMAGE:mcr.microsoft.com/dotnet/framework/runtime:4.8.1:Dotnet-Framework-Runtime-4.8.1"
    "IMAGE:mcr.microsoft.com/powershell:7.4-ubuntu-22.04:Powershell-7.4-Ubuntu"
    "IMAGE:mcr.microsoft.com/azure-powershell:ubuntu-22.04:Azure-Powershell-Ubuntu"
    # powershell_test_deps
    "IMAGE:mcr.microsoft.com/powershell/test-deps:debian-12:Powershell-Test-Deps-Debian-12"
    "IMAGE:mcr.microsoft.com/powershell/test-deps:lts-ubuntu-22.04:Powershell-Test-Deps-Ubuntu-22.04"
    "IMAGE:mcr.microsoft.com/powershell/test-deps:preview-alpine-3.16:Powershell-Test-Deps-Alpine-3.16"
    "IMAGE:mcr.microsoft.com/powershell:preview-7.6-ubuntu-24.04:Powershell-Preview-7.6-Ubuntu-24.04"
    "IMAGE:mcr.microsoft.com/powershell:preview-alpine-3.20:Powershell-Preview-Alpine-3.20"
    # web_servers
    "IMAGE:nginx:1.26-alpine:Nginx-1.26-Alpine"
    "IMAGE:httpd:2.4-alpine:Apache-2.4-Alpine"
    "IMAGE:caddy:2.7-alpine:Caddy-2.7-Alpine"
    "IMAGE:haproxy:2.9-alpine:HAProxy-2.9-Alpine"
    # devops_tools
    "IMAGE:docker:24.0-dind-alpine:Docker-DIND-24.0"
    "IMAGE:registry:2.8:Registry-2.8"
    "IMAGE:portainer/portainer-ce:2.19.1-alpine:Portainer-2.19.1"
    "IMAGE:containrrr/watchtower:latest:Watchtower-Latest"
    "IMAGE:bitnami/kubectl:1.29:Kubectl-1.29"
    "IMAGE:grafana/grafana:10.2.0:Grafana-10.2.0"
    "IMAGE:sonarqube:10.3-community:Sonarqube-10.3"
    "IMAGE:jenkins/jenkins:lts-jdk17:Jenkins-LTS-JDK17"
    # ai_ml
    "IMAGE:pytorch/pytorch:2.1.0-cuda11.8-cudnn8-runtime:PyTorch-2.1-CUDA"
    "IMAGE:tensorflow/tensorflow:2.14.0-gpu:TensorFlow-2.14-GPU"
    "IMAGE:huggingface/transformers-pytorch-gpu:4.35.0:HuggingFace-Transformers-PyTorch"
    "IMAGE:nvidia/cuda:12.0-runtime-ubuntu20.04:NVIDIA-CUDA-12.0-Runtime"
    "IMAGE:jupyter/tensorflow-notebook:latest:Jupyter-TensorFlow-Notebook"
    "IMAGE:jupyter/pytorch-notebook:latest:Jupyter-PyTorch-Notebook"
    "IMAGE:jupyter/datascience-notebook:latest:Jupyter-DataScience-Notebook"
    "IMAGE:mlflow/mlflow:2.8.0:MLflow-2.8.0"
    "IMAGE:wandb/local:latest:Weights-Biases-Local"
    "IMAGE:ollama/ollama:latest:Ollama-Server"
    "IMAGE:vllm/vllm-openai:latest:vLLM-OpenAI-Server"
    "IMAGE:ghcr.io/huggingface/text-generation-inference:latest:HuggingFace-TGI-Server"
    # utilities
    "IMAGE:curlimages/curl:8.5.0:Curl-8.5.0"
    "IMAGE:influxdb:2.7-alpine:InfluxDB-2.7"
    "IMAGE:hashicorp/vault:1.18:Vault-1.18"
    "IMAGE:hashicorp/consul:1.20:Consul-1.20"
    "IMAGE:elasticsearch:8.11.3:Elasticsearch-8.11.3"
    "IMAGE:maven:3.9-eclipse-temurin-17-alpine:Maven-3.9"
    # windows_specific - Only works on Windows Docker hosts
    # "IMAGE:mcr.microsoft.com/windows/server:ltsc2022:Windows-Server-2022"
    # "IMAGE:mcr.microsoft.com/windows/nanoserver:ltsc2025:Windows-NanoServer-2025"
)

# Signal Handling for Graceful Cleanup
cleanup() {
    echo -e "\n🛑 Interrupted - cleaning up..."
    # Remove queue file on interrupt if desired
    # rm -f .docker-pull-state/queue.txt
    echo "Cleanup completed."
    exit 130
}
trap cleanup SIGINT SIGTERM

# Prepare working state
mkdir -p .docker-pull-state
QUEUE_FILE=".docker-pull-state/queue.txt"

# Build queue on first run or reuse existing queue for --resume
if [[ -f "$QUEUE_FILE" && "${RESUME:-false}" == "true" ]]; then
    echo "Resuming from previous queue file: $QUEUE_FILE"
else
    echo "Building new queue..."
    true >"$QUEUE_FILE"
    for entry in "${IMAGES[@]}"; do
        IFS=':' read -r type repo tag friendly <<<"$entry"
        [[ "$SKIP_AI" == "true" && "$type" == "MODEL" ]] && continue
        [[ "$SKIP_WINDOWS" == "true" && "$repo" == mcr.microsoft.com/windows/* ]] && continue
        echo "${type}:${repo}:${tag}:${friendly}" >>"$QUEUE_FILE"
    done
fi

# Total images to pull
TOTAL=$(wc -l <"$QUEUE_FILE")
echo "Total images to pull: $TOTAL"

# Function: Pull single image
pull_image() {
    local entry="$1"
    IFS=':' read -r type repo tag friendly <<<"$entry"
    local image="${repo}:${tag}"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] $friendly ($image)"
        return 0
    fi

    for ((attempt = 1; attempt <= RETRIES + 1; attempt++)); do
        if timeout "$TIMEOUT" docker pull "$image" >>"$LOG_FILE" 2>&1; then
            echo "✓ $friendly" >>"$LOG_FILE"
            return 0
        else
            sleep $((attempt * 2))
        fi
    done
    echo "✗ FAILED: $friendly" >>"$LOG_FILE"
    return 1
}

# Start pulling images sequentially (simplified - no workers)
echo "Starting sequential image pulls..."

current=0
while IFS= read -r line; do
    if [[ -n "$line" ]]; then
        ((current++))
        percent=$((current * 100 / TOTAL))

        printf "\rProgress: %3d%% (%d / %d) - Processing: %s" "$percent" "$current" "$TOTAL" "$(echo "$line" | cut -d: -f4)"

        if pull_image "$line"; then
            [[ "$DEBUG" == "true" ]] && echo -e "\n[DEBUG] Successfully pulled: $line" >&2
        else
            [[ "$DEBUG" == "true" ]] && echo -e "\n[DEBUG] Failed to pull: $line" >&2
        fi
    fi
done <"$QUEUE_FILE"

echo ""
echo "✅ All pull operations finished"

# Final cleanup & reporting
# Remove queue file when successful
rm -f "$QUEUE_FILE"

echo "Log file: $LOG_FILE"

# Summary
echo "Summary:"
echo "  Total attempted: $TOTAL"
echo "  Successful pulls: $(grep -c '✓' "$LOG_FILE" || true)"
echo "  Failed pulls: $(grep -c '✗' "$LOG_FILE" || true)"

# Extra safety disk check post-pull
echo "Final disk usage:"
df -h /
docker system df -v
