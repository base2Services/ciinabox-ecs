#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $DIR/..
rm -rf lib

function pipinstall () {
   if [ $(which pip) == '' ]; then
        echo "ERROR! No pip installed. Try installing either python3 pip or docker"
        exit -1
   fi

   pip install aws-acm-cert-validator==0.1.11 -t lib
}

if [ $(which docker) == '' ]; then
    pipinstall
else
    docker run --rm -v $DIR/..:/dst -w /dst -u $UID python:3-alpine pip install aws-acm-cert-validator==0.1.11 -t lib
fi
