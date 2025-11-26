#############################
# 1. BUILDER (Elixir + Node)
#############################
FROM elixir:1.11.3-alpine as builder

ARG MIX_ENV=prod
ARG NODE_ENV=production
ARG APP_VER=0.0.1
ARG USE_IP_V6=false
ARG REQUIRE_DB_SSL=false
ARG AWS_ACCESS_KEY_ID
ARG AWS_SECRET_ACCESS_KEY
ARG BUCKET_NAME
ARG AWS_REGION
ARG PAPERCUPS_STRIPE_SECRET

ENV APP_VERSION=$APP_VER
ENV REQUIRE_DB_SSL=$REQUIRE_DB_SSL
ENV USE_IP_V6=$USE_IP_V6
ENV AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
ENV AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
ENV BUCKET_NAME=$BUCKET_NAME
ENV AWS_REGION=$AWS_REGION
ENV PAPERCUPS_STRIPE_SECRET=$PAPERCUPS_STRIPE_SECRET
ENV MIX_ENV=prod

WORKDIR /app

# ==================================================
# Install system libs + Node v18 (musl) + npm 8
# ==================================================
RUN apk add --no-cache \
    git bash python3 make gcc g++ libc-dev build-base \
    openssl ncurses-libs erlang erlang-crypto erlang-sasl erlang-inets \
    erlang-runtime-tools erlang-public-key erlang-ssl zlib curl ca-certificates

# Install Node 18 musl binary manually
RUN curl -fsSL https://unofficial-builds.nodejs.org/download/release/v18.17.1/node-v18.17.1-linux-x64-musl.tar.xz \
  | tar -xJ -C /usr/local --strip-components=1

RUN npm install -g npm@8

# --------------------------
# Frontend Step
# --------------------------
COPY assets/package.json assets/package-lock.json ./assets/
RUN npm ci --prefix=assets --legacy-peer-deps

# Fix Webpack 4 + OpenSSL 3 (Node 17+)
ENV NODE_OPTIONS=--openssl-legacy-provider

COPY priv priv
COPY assets assets
RUN npm run build --prefix=assets

# --------------------------
# Backend Step
# --------------------------
COPY mix.exs mix.lock ./
COPY config config/

RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get --only prod

COPY lib lib
RUN mix deps.compile

RUN mix phx.digest priv/static

COPY rel rel
RUN mix release papercups


#############################
# 2. RUNTIME CONTAINER
#############################
FROM alpine:3.13 AS app

RUN apk add --no-cache \
  openssl ncurses-libs zlib bash \
  erlang erlang-crypto erlang-sasl erlang-inets \
  erlang-runtime-tools erlang-public-key erlang-ssl

ENV LANG=C.UTF-8

WORKDIR /app
ENV HOME=/app

# Create unprivileged user
RUN adduser -h /app -u 1000 -s /bin/sh -D papercupsuser

# Copy release
COPY --from=builder --chown=papercupsuser:papercupsuser /app/_build/prod/rel/papercups /app
COPY --from=builder --chown=papercupsuser:papercupsuser /app/priv /app/priv

# IMPORTANT: Give execute permission to BEAM release
RUN chmod -R 755 /app/releases || true

# Entrypoint
COPY docker-entrypoint.sh /entrypoint.sh
RUN chmod a+x /entrypoint.sh

USER papercupsuser
EXPOSE 4000
WORKDIR /app

ENTRYPOINT ["/entrypoint.sh"]
CMD ["run"]
