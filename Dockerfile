FROM elixir-dev

RUN apk --no-cache add openssl && \
    mkdir -p /app
WORKDIR /app
COPY mix.* ./
COPY lib ./lib
RUN mix deps.get && MIX_ENV=prod mix escript.build
CMD ["./anvil", "server"]
