# Docker Pull Essentials

A robust, production-ready script suite for pulling essential Docker images and AI/ML models for development environments.

## Features

- ✅ **Parallel Processing**: Configurable parallel workers for faster downloads
- ✅ **Retry Logic**: Automatic retry with exponential backoff
- ✅ **Environment Detection**: Auto-detects WSL2 vs native Linux
- ✅ **Comprehensive Logging**: Timestamped logs with multiple levels
- ✅ **Progress Tracking**: Real-time progress indicators
- ✅ **Dry Run Mode**: Preview what would be pulled
- ✅ **Categorized Images**: Organized by purpose (databases, languages, etc.)
- ✅ **Cross-Platform**: Bash script + PowerShell wrapper
- ✅ **Error Handling**: Proper exit codes and error reporting
- ✅ **Configuration**: YAML config file support

## Quick Start

### Linux/WSL2
```bash
chmod +x docker-pull-essentials.sh
./docker-pull-essentials.sh
```

### Windows (PowerShell)
```powershell
.\docker-pull-essentials.ps1
```

## Usage Examples

### Basic Usage
```bash
# Pull all images with defaults
./docker-pull-essentials.sh

# Dry run to see what would be pulled
./docker-pull-essentials.sh --dry-run

# Use 8 parallel workers
./docker-pull-essentials.sh --parallel 8

# Skip AI/ML models
./docker-pull-essentials.sh --skip-ai

# Skip Windows images (auto-detected in WSL2)
./docker-pull-essentials.sh --skip-windows
```

### Advanced Usage
```bash
# Custom configuration
./docker-pull-essentials.sh --parallel 6 --retry 3 --timeout 600

# Enable debug logging
DEBUG=true ./docker-pull-essentials.sh

# Custom log file
./docker-pull-essentials.sh --log-file /var/log/docker-pull.log
```

## Image Categories

### Base OS / Essentials
- `ubuntu:latest`
- `debian:latest` 
- `alpine:latest`

### Programming Languages
- `python:latest`
- `node:latest`
- `openjdk:latest`
- `golang:latest`
- `ruby:latest`
- `php:latest`

### Databases
- `postgres:latest`
- `mysql:latest`
- `mariadb:latest`
- `mongo:latest`
- `redis:latest`
- `redis/redis-stack:latest`
- `pgvector/pgvector:latest`
- `myscale/myscaledb:latest`

### Microsoft/.NET
- `mcr.microsoft.com/dotnet/sdk:9.0`
- `mcr.microsoft.com/dotnet/aspnet:9.0`
- `mcr.microsoft.com/dotnet/runtime:9.0`
- `mcr.microsoft.com/powershell:latest`
- `mcr.microsoft.com/azure-powershell:ubuntu-22.04`

### PowerShell Test Dependencies
- `mcr.microsoft.com/powershell/test-deps:debian-12`
- `mcr.microsoft.com/powershell/test-deps:lts-ubuntu-22.04`
- `mcr.microsoft.com/powershell/test-deps:preview-alpine-3.16`
- `mcr.microsoft.com/powershell:preview-7.6-ubuntu-24.04`
- `mcr.microsoft.com/powershell:preview-alpine-3.20`

### Web Servers / Proxies
- `nginx:latest`
- `httpd:latest`
- `caddy:latest`
- `haproxy:latest`

### DevOps / CI Tools
- `docker:latest`
- `registry:latest`
- `portainer/portainer-ce:latest`
- `jenkins/jenkins:lts-jdk17`
- `grafana/grafana:latest`
- `sonarqube:latest`

### AI/ML Models
- `ai/llama3.2:latest`
- `ai/mistral:latest`
- `ai/deepcoder-preview`
- `ai/smollm2:latest` (model)
- `ai/llama3.3:latest` (model)
- `ai/phi4:latest` (model)
- `ai/qwen2.5:latest` (model)
- `ai/mxbai-embed-large:latest` (model)

### Utilities
- `curlimages/curl:latest`
- `influxdb:latest`
- `vault:latest`
- `consul:latest`
- `elasticsearch:latest`
- `maven:latest`

## Configuration

### Command Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `--dry-run` | Show what would be pulled | false |
| `--parallel NUM` | Number of parallel workers | 4 |
| `--retry NUM` | Retry attempts per image | 2 |
| `--timeout SEC` | Timeout per pull (seconds) | 300 |
| `--skip-ai` | Skip AI/ML models | false |
| `--skip-windows` | Skip Windows images | false |
| `--log-file FILE` | Log output file | docker-pull.log |
| `--help` | Show help message | - |

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DOCKER_PULL_TIMEOUT` | Override default timeout | 300 |
| `DOCKER_PULL_RETRIES` | Override default retries | 2 |
| `DOCKER_PULL_PARALLEL` | Override parallel count | 4 |
| `DEBUG` | Enable debug logging | false |

### Configuration File

Use `docker-pull-config.yaml` to define custom image sets and environment-specific settings:

```yaml
settings:
  timeout: 300
  retries: 2
  parallel: 4
  skip_ai: false

categories:
  base_os:
    enabled: true
    images:
      - "ubuntu:latest"
      - "debian:latest"
```

## Environment Detection

The script automatically detects your environment:

### WSL2 Detection
- Checks `/proc/version` for "microsoft" string
- Automatically skips Windows-specific images
- Optimizes parallel workers for WSL2

### Native Linux
- Full feature support
- Can pull Windows containers (if Docker supports it)
- Higher default parallel workers

## Error Handling

### Exit Codes
- `0` - Success
- `1` - General error
- `2` - Docker not available
- `126` - Permission denied
- `130` - Interrupted by user

### Retry Logic
- Exponential backoff (2^attempt seconds)
- Configurable retry attempts
- Per-image timeout handling

## Logging

### Log Levels
- `INFO` - General information
- `WARN` - Warnings (non-fatal)
- `ERROR` - Errors (may be fatal)
- `DEBUG` - Detailed debugging (enable with `DEBUG=true`)

### Log Format
```
2025-06-11 10:30:45 [docker-pull-essentials.sh] INFO: Starting Docker image pulls...
```

## Performance Optimization

### Parallel Processing
- Default: 4 workers
- WSL2: Automatically reduced to 2
- Native Linux: Can use up to 8+

### Network Optimization
- Configurable timeouts
- Retry with exponential backoff
- Parallel downloads for faster completion

### Disk Space Management
- Warns when disk space < 10GB
- Reports total Docker image sizes
- Suggests cleanup if needed

## Best Practices

### Security
- Input validation for all parameters
- Proper quoting of variables
- No sudo required for Docker operations
- Secure temporary file handling

### Reliability
- Strict error handling (`set -euo pipefail`)
- Comprehensive prerequisite checks
- Graceful cleanup on interruption
- Detailed error reporting

### Maintainability
- Modular function design
- Comprehensive documentation
- Consistent coding standards
- Version tracking

## Troubleshooting

### Common Issues

#### Docker Not Found
```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
```

#### Permission Denied
```bash
# Add user to docker group
sudo usermod -aG docker $USER
# Logout and login again
```

#### WSL2 Performance
```bash
# Use fewer parallel workers
./docker-pull-essentials.sh --parallel 2
```

#### Network Timeouts
```bash
# Increase timeout
./docker-pull-essentials.sh --timeout 600
```

### Debug Mode
Enable detailed logging:
```bash
DEBUG=true ./docker-pull-essentials.sh
```

## File Structure

```
ubuntudev/
├── docker-pull-essentials.sh      # Main bash script
├── docker-pull-essentials.ps1     # PowerShell wrapper
├── docker-pull-config.yaml        # Configuration file
├── README.md                       # This file
└── docker-pull.log                # Generated log file
```

## Requirements

### Linux/WSL2
- Bash 4.0+
- Docker 20.0+
- GNU coreutils (timeout, mktemp, etc.)

### Windows
- PowerShell 7.0+
- Docker Desktop
- WSL2 (recommended) or Git Bash/MSYS2

## Contributing

1. Follow the coding standards in the global instructions
2. Test in both WSL2 and native Linux environments
3. Update documentation for any new features
4. Include error handling and logging for new code

## License

This script suite is part of the Ubuntu Development Environment setup.

## Version History

- **v1.1.0** - Enhanced with parallel processing, retry logic, and comprehensive error handling
- **v1.0.0** - Initial version with basic pull functionality
