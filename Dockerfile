# syntax=docker/dockerfile:1
FROM elixir:1.19-otp-28-slim
ENV MIX_ENV=prod
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates curl xz-utils && rm -rf /var/lib/apt/lists/*
ARG NODE_VERSION=24.11.1
RUN --mount=type=secret,id=extra_ca,required=false CA=""; if [ -s /run/secrets/extra_ca ]; then cat /etc/ssl/certs/ca-certificates.crt /run/secrets/extra_ca > /tmp/ca.pem; CA="--cacert /tmp/ca.pem"; fi; curl -fsSL $CA https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz -o /tmp/node.tar.xz && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 && rm -f /tmp/node.tar.xz /tmp/ca.pem && node --version
RUN --mount=type=secret,id=extra_ca,required=false if [ -s /run/secrets/extra_ca ]; then cp /run/secrets/extra_ca /usr/local/share/ca-certificates/extra.crt && update-ca-certificates; fi
ENV HEX_CACERTS_PATH=/etc/ssl/certs/ca-certificates.crt
RUN ERL_FLAGS="+JMsingle true" mix local.hex --force && ERL_FLAGS="+JMsingle true" mix local.rebar --force
COPY mix.exs mix.lock ./
RUN ERL_FLAGS="+JMsingle true" mix deps.get --only prod && ERL_FLAGS="+JMsingle true" mix deps.compile
COPY lib lib
COPY priv priv
COPY scripts scripts
COPY bench bench
RUN ERL_FLAGS="+JMsingle true" mix compile
RUN rm -f /usr/local/share/ca-certificates/extra.crt && update-ca-certificates --fresh >/dev/null
ENV PORT=8080
ENV ERL_FLAGS="+JMsingle true -noinput"
EXPOSE 8080
CMD ["mix", "run", "--no-halt", "--no-compile"]
