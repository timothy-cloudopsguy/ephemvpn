# WireGuard VPN container with built-in key generation
FROM ghcr.io/irctrakz/wgslirp:latest

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
