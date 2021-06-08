#!/bin/bash

set -xe

cp -fr /opt/plrfs/notebooks /tmp/PLR
chown ${NB_USER}:users -R /tmp/PLR
cp -fr --preserve /tmp/PLR /home/${NB_USER}/

supervisord -c /opt/supervisor/supervisor.conf

export SUPERVISOR_INITIALIZED=1
