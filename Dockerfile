#############################
# 1. BUILDER (Elixir + Node)
#############################
FROM elixir:1.11.3-alpine as builder

ARG MIX_ENV=prod
ENV MIX_ENV=prod

WORKDIR /app

# Basic deps + erlang built-in from the base image
RUN apk add --no-cache \
    git bash python3 make gcc g++ libc-dev build-base \
    openssl ncurses-libs zlib curl ca-certificates

# --- Install Node 18 MUSL ---
RUN curl -fsSL https://unofficial-builds.nodejs.org/download/release/v18.17.1/node-v18.17.1-linux-x64-musl.tar.xz \
  | tar -xJ -C /usr/local --strip-components=1

RUN npm install -g npm@8


#############################
# Frontend build
#############################
COPY assets/package.json assets/package-lock.json ./assets/
RUN npm ci --prefix=assets --legacy-peer-deps

# Fix webpack + OpenSSL3 issue
ENV NODE_OPTIONS=--openssl-legacy-provider

COPY priv priv
COPY assets assets
RUN npm run build --prefix=assets


#############################
# Backend build
#############################
COPY mix.exs mix.lock ./
COPY config config/
RUN mix local.hex --force && mix local.rebar --force && mix deps.get --only prod

COPY lib lib
RUN mix deps.compile
RUN mix phx.digest priv/static

COPY rel rel
RUN mix release papercups



#############################
# 2. RUNTIME
#############################
FROM alpine:3.13 AS app

# OTP libs needed for Elixir release (bundled with alpine 3.13)
RUN apk add --no-cache \
    openssl ncurses-libs zlib bash erlang erlang-ssl erlang-inets erlang-public-key

ENV LANG=C.UTF-8
WORKDIR /app
ENV HOME=/app

RUN adduser -h /app -u 1000 -s /bin/sh -D papercupsuser

COPY --from=builder --chown=papercupsuser:papercupsuser /app/_build/prod/rel/papercups /app
COPY --from=builder --chown=papercupsuser:papercupsuser /app/priv /app/priv

RUN chmod -R 755 /app/releases

COPY docker-entrypoint.sh /entrypoint.sh
RUN chmod a+x /entrypoint.sh

USER papercupsuser
EXPOSE 4000

ENTRYPOINT ["/entrypoint.sh"]
CMD ["run"]
