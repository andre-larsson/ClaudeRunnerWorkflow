#! /bin/bash

./generate-contexts.sh $1 && ./claude-runner.sh $1.new