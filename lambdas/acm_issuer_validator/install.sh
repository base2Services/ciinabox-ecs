#!/bin/bash

rm -rf lib/*

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
rm -rf $DIR/lib/*

docker run --rm -v $DIR:/dst -w /dst -u 1000 python:3-alpine pip install aws-acm-cert-validator==0.1.11 -t lib
