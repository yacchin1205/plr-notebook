FROM jupyter/scipy-notebook

USER root
RUN apt-get update && \
    apt-get install -y openjdk-8-jre pkg-config fuse3 libfuse3-dev \
            curl zip rabbitmq-server supervisor && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
ENV JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk-amd64/
RUN pip install --no-cache-dir pyfuse3 pexpect

USER $NB_USER
RUN curl -s "https://get.sdkman.io" | bash
RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh; sdk install groovy"

USER root
COPY . /tmp

## PLR binary files
#RUN cp -fr /tmp/plr /opt/ && \
#    chmod +x /opt/plr/bin/plr && \
#    mkdir /home/$NB_USER/.groovy && \
#    cp -fr /opt/plr/lib /home/$NB_USER/.groovy/ && \
#    chown $NB_USER -R /home/$NB_USER/.groovy
# ENV PATH=$PATH:/opt/plr/bin

# PLRFS scripts
RUN mkdir /opt/plrfs && cp -fr /tmp/* /opt/plrfs/ && \
    chmod +x /opt/plrfs/groovy/*.sh && \
    pip install --no-cache-dir /opt/plrfs/

COPY conf /tmp/conf

# Scripts for Supervisor
RUN mkdir -p /usr/local/bin/before-notebook.d && \
    cp /tmp/conf/onboot/* /usr/local/bin/before-notebook.d/ && \
    chmod +x /usr/local/bin/before-notebook.d/* && \
    cp -fr /tmp/conf/supervisor /opt/
RUN chown $NB_USER -R /tmp/notebooks

USER $NB_USER
RUN cp /tmp/notebooks/* .
