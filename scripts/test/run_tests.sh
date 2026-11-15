#!/usr/bin/env bash
# Run the test suite in throwaway Docker containers (Carceral Consultation,
# 2026-11-13). Elixir isn't installed on the Mac, so this uses the same
# Elixir image the app is built with, plus a temporary PostgreSQL that
# publishes no ports. The running app and its database are not touched.
#
#   scripts/test/run_tests.sh                       # whole suite
#   scripts/test/run_tests.sh test/claper/embeds_test.exs
#
# Compiled dependencies are cached in the Docker volume cc-test-build, so
# runs after the first take about a minute. `docker volume rm cc-test-build`
# clears the cache.
#
# config/runtime.exs replaces the test secret with SECRET_KEY_BASE from the
# environment (nil when unset, which breaks every test that uses a session),
# so each run gets a random, test-only key.
set -euo pipefail
cd "$(dirname "$0")/../.."

IMAGE="hexpm/elixir:1.18.4-erlang-28.0.1-ubuntu-noble-20250619"
DB="cc-testdb"

cleanup() { docker stop "$DB" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker stop "$DB" >/dev/null 2>&1 || true
docker run -d --rm --name "$DB" -e POSTGRES_USER=claper -e POSTGRES_PASSWORD=claper postgres:15 >/dev/null
until docker exec "$DB" pg_isready -U claper >/dev/null 2>&1; do sleep 1; done

docker run --rm --network "container:$DB" \
  -e MIX_ENV=test \
  -e SECRET_KEY_BASE="$(openssl rand -base64 48 | tr -d '\n')" \
  -v "$PWD":/src:ro -v cc-test-build:/work \
  "$IMAGE" bash -c '
    set -e
    command -v git >/dev/null && command -v make >/dev/null || {
      apt-get update -qq >/dev/null && apt-get install -y -qq git build-essential >/dev/null; }
    mkdir -p /work/app && cd /work/app
    rm -rf lib test config priv
    cp -r /src/mix.exs /src/mix.lock /src/lib /src/test /src/config /src/priv .
    mix local.hex --force >/dev/null && mix local.rebar --force >/dev/null
    mix deps.get >/dev/null
    mix test "$@"
  ' bash "$@"
