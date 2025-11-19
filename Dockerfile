# GitHub - Multi-stage Docker build
#
# This Dockerfile creates a production-ready image for GitHub
# with support for CLI, REST API.
#
# Build: docker build -t github:latest .
# Run CLI: docker run github:latest github --help
# Run API: docker run -p 8000:8000 github:latest

# Multi-stage build:
# 1. builder: Install dependencies and build
# 2. runtime: Minimal production image

# ============================================================================
# Stage 1: Builder
# ============================================================================

FROM python:3.14-slim AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    make \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /build

# Copy dependency files
COPY pyproject.toml setup.py README.md ./

# Create virtual environment
RUN python -m venv /opt/venv

# Activate virtual environment
ENV PATH="/opt/venv/bin:$PATH"

# Upgrade pip, setuptools, wheel
RUN pip install --no-cache-dir --upgrade pip setuptools wheel

# Install dependencies (not the package itself yet)
RUN pip install --no-cache-dir -e .

# Copy source code
COPY github/ ./github/

# Install the package
RUN pip install --no-cache-dir .

# ============================================================================
# Stage 2: Runtime
# ============================================================================

FROM python:3.14-slim AS runtime

# Install runtime dependencies only
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd --create-home --shell /bin/bash appuser

# Set working directory
WORKDIR /app

# Copy virtual environment from builder
COPY --from=builder /opt/venv /opt/venv

# Copy application code (needed for imports)
COPY --from=builder /build/github /app/github

# Set ownership
RUN chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Activate virtual environment
ENV PATH="/opt/venv/bin:$PATH"

# Set Python environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Application environment variables
ENV GITHUB_ENV=production \
    GITHUB_LOG_LEVEL=INFO \
    GITHUB_API_HOST=0.0.0.0 \
    GITHUB_API_PORT=8000

# Expose API port
EXPOSE 8000

# Health check for API
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Default command: Run REST API server
CMD ["uvicorn", "github.interfaces.rest:app", "--host", "0.0.0.0", "--port", "8000"]

# Alternative commands:
# CLI: docker run github:latest github --help
# API (production): docker run github:latest gunicorn github.interfaces.rest:app --workers 4 --worker-class uvicorn.workers.UvicornWorker --bind 0.0.0.0:8000

# ============================================================================
# Build Arguments (optional)
# ============================================================================

# Usage:
# docker build --build-arg PYTHON_VERSION=3.12 -t github:latest .

ARG PYTHON_VERSION=3.11
ARG APP_VERSION=0.1.0

# Labels (OCI image spec)
LABEL org.opencontainers.image.title="GitHub" \
      org.opencontainers.image.description="Multi-interface capability server (CLI/REST)" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.authors="your.email@example.com" \
      org.opencontainers.image.source="https://github.com/yourusername/github" \
      org.opencontainers.image.licenses="MIT"

# ============================================================================
# Development Image (optional)
# ============================================================================

# Build development image:
# docker build --target development -t github:dev .

FROM runtime AS development

USER root

# Install development dependencies
RUN apt-get update && apt-get install -y \
    git \
    vim \
    && rm -rf /var/lib/apt/lists/*

# Copy development dependencies
COPY --from=builder /build/pyproject.toml /app/

# Install dev dependencies
RUN /opt/venv/bin/pip install --no-cache-dir -e ".[dev]"

# Switch back to non-root user
USER appuser

# Set development environment
ENV GITHUB_ENV=development \
    GITHUB_LOG_LEVEL=DEBUG

# Default command for development: shell
CMD ["/bin/bash"]
