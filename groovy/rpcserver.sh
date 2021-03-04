#!/bin/bash

set -xe

source ~/.sdkman/bin/sdkman-init.sh

if [ -f ~/.plrprofile ]; then
  source ~/.plrprofile
fi

groovy /opt/plrfs/groovy/rpcserver.groovy
