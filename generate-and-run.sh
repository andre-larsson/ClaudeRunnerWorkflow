#! /bin/bash
set -x

./generate-contexts.sh $1 && ./claude-runner.sh $1.new
