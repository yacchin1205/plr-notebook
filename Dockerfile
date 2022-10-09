FROM jupyter/scipy-notebook

USER root
RUN apt-get update && \
    apt-get install -y openjdk-8-jre pkg-config fuse3 libfuse3-dev \
            curl zip rabbitmq-server supervisor gnupg apt-transport-https && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
ENV JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk-amd64/
RUN apt-get update && \
    apt-get install -y build-essential && \
    pip install --no-cache-dir pyfuse3 pexpect && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

ENV SDKMAN_DIR=/opt/sdkman
RUN curl -s "https://get.sdkman.io" | bash
RUN bash -c "source ${SDKMAN_DIR}/bin/sdkman-init.sh; sdk install groovy"

# Dart
RUN wget -qO- https://dl-ssl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/dart.gpg && \
    echo 'deb [signed-by=/usr/share/keyrings/dart.gpg arch=amd64] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main' | tee /etc/apt/sources.list.d/dart_stable.list && \
    apt-get update && \
    apt-get install -y dart && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
ENV PATH=$PATH:/usr/lib/dart/bin

COPY . /tmp

# PLRFS scripts
RUN mkdir /opt/plrfs && cp -fr /tmp/* /opt/plrfs/ && \
    chmod +x /opt/plrfs/groovy/*.sh && \
    pip install --no-cache-dir /opt/plrfs/

## PLR binary files
RUN unzip /opt/plrfs/archive/plr.zip -d /tmp && \
    mv /tmp/plr/* /opt/plrfs/ && \
    chmod +x /opt/plrfs/bin/plr
#    mkdir /home/$NB_USER/.groovy && \
#    cp -fr /opt/plr/lib /home/$NB_USER/.groovy/ && \
#    chown $NB_USER -R /home/$NB_USER/.groovy
ENV PATH=$PATH:/opt/plrfs/bin

# Scripts for Supervisor
RUN mkdir -p /usr/local/bin/before-notebook.d && \
    cp /tmp/conf/onboot/* /usr/local/bin/before-notebook.d/ && \
    chmod +x /usr/local/bin/before-notebook.d/* && \
    cp -fr /tmp/conf/supervisor /opt/
RUN chown $NB_USER -R /tmp/notebooks

# Boot scripts to perform /usr/local/bin/before-notebook.d/* on JupyterHub
RUN mkdir -p /opt/plr-notebook/original/bin/ && \
    mv /opt/conda/bin/jupyterhub-singleuser /opt/plr-notebook/original/bin/jupyterhub-singleuser && \
    mv /opt/conda/bin/jupyter-notebook /opt/plr-notebook/original/bin/jupyter-notebook && \
    cp /tmp/conf/bin/* /opt/conda/bin/ && \
    chmod +x /opt/conda/bin/jupyterhub-singleuser /opt/conda/bin/jupyter-notebook

USER $NB_USER
RUN cp /tmp/notebooks/* .
