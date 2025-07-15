FROM dart:sdk AS plrfs-builder

COPY . /tmp

# Build the PLR command-line tool
RUN mkdir -p /tmp/lib /tmp/bin && \
    unzip /tmp/archive/plrDart.zip -d /tmp/lib && \
    # Remove flutter-related dependencies from plrDart's pubspec.yaml
    # because we are not using Flutter in this Docker image
    sed -i '/plr_ui/d;/plr_flutter/d' /tmp/lib/plrDart/pubspec.yaml && \
    cd /tmp/lib/plrDart/_plr_common && \
    dart pub get && \
    dart run build_runner build --delete-conflicting-outputs && \
    cd /tmp/lib/plrDart/plr_command && \
    dart pub get && \
    dart compile exe bin/plr.dart -o /tmp/bin/plr

# Build the PLR RPC server
RUN mv /tmp/dart/plrget /tmp/lib/plrDart/ && \
    cd /tmp/lib/plrDart/plrget && \
    dart pub get && \
    dart compile exe plrget.dart -o /tmp/bin/plrget

FROM quay.io/jupyter/scipy-notebook

USER root
RUN apt-get update && \
    apt-get install -y \
            curl zip supervisor gnupg libfuse3-dev fuse3 \
            sqlite3 libsqlite3-dev pkg-config && \
    pip install --no-cache-dir pyfuse3 pexpect && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY . /tmp

# PLRFS scripts
RUN mkdir /opt/plrfs && cp -fr /tmp/* /opt/plrfs/ && \
    pip install --no-cache-dir /opt/plrfs/

## PLR binary files
COPY --from=plrfs-builder /tmp/bin /opt/plrfs/bin
ENV PATH=$PATH:/opt/plrfs/bin

USER $NB_USER
RUN cp /tmp/notebooks/* .
