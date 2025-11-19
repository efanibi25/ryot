ARG NODE_BASE_IMAGE=node:20.10.0-bookworm-slim

# Stage 1: Frontend build base
FROM $NODE_BASE_IMAGE AS frontend-build-base
ENV MOON_TOOLCHAIN_FORCE_GLOBALS=true
WORKDIR /app
RUN apt update && apt install -y --no-install-recommends git curl ca-certificates xz-utils
RUN npm install -g @moonrepo/cli && moon --version

# Stage 2: Frontend workspace
FROM frontend-build-base AS frontend-workspace
WORKDIR /app
COPY . .
RUN moon docker scaffold frontend

# Stage 3: Frontend builder
FROM frontend-build-base AS frontend-builder
WORKDIR /app
COPY --from=frontend-workspace /app/.moon/docker/workspace .
RUN moon docker setup
COPY --from=frontend-workspace /app/.moon/docker/sources .
RUN moon run frontend:build
RUN moon docker prune

# Stage 4: Build backend binaries
FROM rust:1-bookworm AS backend-builder

# Build-time arguments
ARG DATABASE_URL
ARG DEFAULT_TMDB_ACCESS_TOKEN
ARG DEFAULT_MAL_CLIENT_ID
ARG TRAKT_CLIENT_ID
ARG UNKEY_API_ID
ARG APP_VERSION

# Runtime environment variables
ENV DATABASE_URL=${DATABASE_URL}
ENV DEFAULT_TMDB_ACCESS_TOKEN=${DEFAULT_TMDB_ACCESS_TOKEN}
ENV DEFAULT_MAL_CLIENT_ID=${DEFAULT_MAL_CLIENT_ID}
ENV TRAKT_CLIENT_ID=${TRAKT_CLIENT_ID}
ENV UNKEY_API_ID=${UNKEY_API_ID}
ENV APP_VERSION=${APP_VERSION}

# Install dependencies for x86_64
RUN apt-get update && \
    apt-get install -y \
        libssl-dev \
        pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Add the x86_64 target
RUN rustup target add x86_64-unknown-linux-gnu

WORKDIR /app
COPY . .
# ADD THIS LINE to reduce memory usage during the build
ENV CARGO_BUILD_JOBS=2

# Build for x86_64
RUN cargo build --release --target x86_64-unknown-linux-gnu

# Stage 5: Final image
FROM $NODE_BASE_IMAGE
ARG TARGETARCH
ENV TARGETARCH=${TARGETARCH}
LABEL org.opencontainers.image.source="https://github.com/IgnisDa/ryot"
LABEL org.opencontainers.image.description="The only self hosted tracker you will ever need!"
ENV FRONTEND_UMAMI_SCRIPT_URL="https://umami.diptesh.me/script.js"
ENV FRONTEND_UMAMI_WEBSITE_ID="5ecd6915-d542-4fda-aa5f-70f09f04e2e0"
RUN apt-get update && apt-get install -y --no-install-recommends wget curl ca-certificates procps libc6
RUN wget http://ftp.debian.org/debian/pool/main/o/openssl/libssl1.1_1.1.1w-0+deb11u1_${TARGETARCH}.deb && dpkg -i libssl1.1_1.1.1w-0+deb11u1_${TARGETARCH}.deb && rm -rf libssl1.1_1.1.1w-0+deb11u1_${TARGETARCH}.deb
RUN rm -rf /var/lib/apt/lists/*
COPY --from=caddy:2.9.1 /usr/bin/caddy /usr/local/bin/caddy
RUN npm install --global concurrently@9.1.2 && concurrently --version
RUN useradd -m -u 1001 ryot
WORKDIR /home/ryot
USER ryot
COPY ci/Caddyfile /etc/caddy/Caddyfile
COPY --from=frontend-builder --chown=ryot:ryot /app/apps/frontend/node_modules ./node_modules
COPY --from=frontend-builder --chown=ryot:ryot /app/apps/frontend/package.json ./package.json
COPY --from=frontend-builder --chown=ryot:ryot /app/apps/frontend/build ./build

#Copy the backend binary directly from the backend-builder stage
COPY --from=backend-builder --chown=ryot:ryot /app/target/x86_64-unknown-linux-gnu/release/backend /usr/local/bin/backend
RUN chmod +x /usr/local/bin/backend

CMD [ \
   "concurrently", "--names", "frontend,backend,proxy", "--kill-others", \
   "PORT=3000 npx react-router-serve ./build/server/index.js", \
   "BACKEND_PORT=5000 /usr/local/bin/backend", \
   "caddy run --config /etc/caddy/Caddyfile" \
   ]
