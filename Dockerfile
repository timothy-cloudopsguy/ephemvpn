# --- Build stage ---
FROM golang:1.23-alpine AS build
WORKDIR /src

RUN apk add --no-cache git && git clone -b icmpfix https://github.com/timothy-cloudopsguy/wgslirp /src

# Speed up builds by caching deps (none yet, but keep pattern)
# COPY go.mod go.sum ./
RUN go mod download

# Build static-ish binary
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o wgslirp ./cmd/wgslirp

# --- Runtime stage ---
FROM alpine:3.20 as runtime
RUN apk add --no-cache ca-certificates

# Create a non-root user and group
RUN addgroup -S wgslirp && adduser -S -G wgslirp wgslirp

WORKDIR /app
COPY --from=build /src/wgslirp /usr/local/bin/wgslirp
# Default configuration can be overridden via env

# Ensure proper permissions
RUN chown -R wgslirp:wgslirp /app

EXPOSE 51820/udp

# Switch to non-root user
USER wgslirp

# ENTRYPOINT ["/usr/local/bin/wgslirp"]

# Switch to root to install additional dependencies
USER root

# Install Python and additional dependencies
RUN apk add aws-cli \
    py3-pip \
    uvicorn \
    curl \
    bash \
    openssl \
    wireguard-tools

# Install Poetry for Python dependency management
RUN pip3 install --no-cache-dir --break-system-packages poetry

# Set working directory
WORKDIR /app

# Copy Python project files
COPY api/ ./api/
COPY pyproject.toml ./pyproject.toml
COPY poetry.lock ./poetry.lock

# Install Python dependencies
WORKDIR /app
RUN poetry install

WORKDIR /app

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose ports (WireGuard UDP + API)
EXPOSE 51820/udp
EXPOSE 8000/tcp

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]
