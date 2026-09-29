# The relay for the raycaster badges. Build and run:
#
#   docker build -t evilgoat-relay .
#   docker run -d --name evilgoat-relay -p 4040:4040 -e RELAY_TOKEN=... evilgoat-relay
#
# RELAY_TOKEN (optional) is a shared token badges must send; RELAY_MAX is the most
# connections at once (200); PORT is the port inside the container (4040).
FROM elixir:1.19-slim

ENV MIX_ENV=prod
WORKDIR /app

# The slim image has no CA certificates, and Hex is fetched over HTTPS.
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Dependencies first, so they are only rebuilt when they change.
COPY mix.exs mix.lock ./
RUN mix local.hex --force && mix local.rebar --force \
    && mix deps.get --only prod && mix deps.compile

COPY config config
COPY lib lib
RUN mix compile

EXPOSE 4040

# Not a release: one process, and nothing to unpack.
CMD ["mix", "run", "--no-halt"]
