FROM ghcr.io/opentofu/opentofu:minimal AS tofu

FROM ubuntu:24.04

# Copy the tofu binary
COPY --from=tofu /usr/local/bin/tofu /usr/local/bin/tofu

# Install dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace