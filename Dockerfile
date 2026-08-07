FROM ghcr.io/gleam-lang/gleam:v1.14.0-erlang@sha256:f892860f9bbfb5a3382b498e743bf20e5dfe6c89c880b46a8f795515944e1411

WORKDIR /app

RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential make \
 && rm -rf /var/lib/apt/lists/*

COPY .vendor/.zed/oresoftware/flags-2-env ./.vendor/.zed/oresoftware/flags-2-env

# Gleam reaches the C core through an Erlang NIF, not through a shared library
# loaded at runtime: flags2env_native.erl is compiled to BEAM and the NIF .so is
# placed in that module's priv/ directory, where erlang:load_nif finds it.
RUN mkdir -p /app/erlang_libs/flags2env_native/ebin /app/erlang_libs/flags2env_native/priv \
 && erlc -o /app/erlang_libs/flags2env_native/ebin .vendor/.zed/oresoftware/flags-2-env/clients/gleam/flags2env_native.erl \
 && ERL_INCLUDE="$(erl -noshell -eval 'io:format("~s/erts-~s/include", [code:root_dir(), erlang:system_info(version)]), halt().')" \
 && cc -std=c99 -DF2E_BEAM_MODULE_NATIVE -fPIC -shared \
      -I"$ERL_INCLUDE" -I.vendor/.zed/oresoftware/flags-2-env/clients/erlang/c_src \
      .vendor/.zed/oresoftware/flags-2-env/clients/erlang/c_src/flags2env_nif.c \
      .vendor/.zed/oresoftware/flags-2-env/clients/erlang/c_src/parser.c \
      -o /app/erlang_libs/flags2env_native/priv/flags2env_nif.so

COPY .cli-flags.toml ./
COPY gleam.toml manifest.toml ./
COPY src ./src

ENV ERL_LIBS=/app/erlang_libs

# The Gleam client module is copied in rather than declared as a Hex dependency:
# it is not published, and .zpkg.toml is the declaration of record here.
RUN cp .vendor/.zed/oresoftware/flags-2-env/clients/gleam/src/flags2env.gleam src/flags2env.gleam \
 && gleam build

RUN useradd --create-home --shell /bin/sh --uid 10001 fixture
# gleam run touches build/ even when everything is already compiled, so that one
# directory is handed to the runtime user. The rest of /app stays root-owned.
RUN chown -R fixture:fixture /app/build
USER fixture
ENV HOME=/tmp

CMD ["gleam", "run", "-m", "demo"]
