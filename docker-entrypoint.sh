#!/bin/sh
set -e

if [ "$1" = "run" ]; then
    echo "Running database migrations..."
    /app/bin/papercups eval "ChatApi.Release.migrate()"

    echo "Starting Papercups..."
    exec /app/bin/papercups start
fi

exec "$@"
