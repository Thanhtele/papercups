# --------------------------------------------------------
# BUILDER
# --------------------------------------------------------
FROM elixir:1.11.3-alpine AS builder

ENV MIX_ENV=prod

# Install build dependencies
RUN apk update && apk add --no-cache \
  git curl wget build-base \
  nodejs npm yarn python3 \
  ca-certificates openssl ncurses-libs erlang

# --- FIX Node version ---
# Remove old npm that breaks build
RUN npm install -g npm@8 && npm cache clean --force

WORKDIR /app

# Install hex & rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Install Elixir deps
COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only prod && mix deps.compile

# Install JS deps
COPY assets/package.json assets/package-lock.json ./assets/
RUN npm install --prefix=assets --legacy-peer-deps

# Build assets
COPY assets assets
RUN npm run --prefix=assets deploy
RUN mix phx.digest

# Build release
COPY lib lib
COPY priv priv
RUN mix release

# --------------------------------------------------------
# APP
# --------------------------------------------------------
FROM alpine:3.13 AS app

RUN apk add --no-cache openssl ncurses-libs

WORKDIR /app
RUN adduser -S papercupsuser

COPY --from=builder /app/_build/prod/rel/papercups ./

USER papercupsuser

CMD ["bin/papercups", "start"]
