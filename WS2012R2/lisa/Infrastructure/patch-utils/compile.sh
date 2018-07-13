#!/bin/bash
set -xe

COMPILE_DIR=$1
COMPILE_TYPE=$2

pushd "${COMPILE_DIR}"
     make -C "/lib/modules/$(uname -r)/build" M=$(pwd) $COMPILE_TYPE
     make -C "./tools" $COMPILE_TYPE
popd

