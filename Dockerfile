FROM elixir:1.15

RUN apt-get update && apt-get install -y \
  build-essential \
  npm

WORKDIR /app

RUN mix local.hex --force \
 && mix local.rebar --force \
 && mix archive.install hex phx_new --force
