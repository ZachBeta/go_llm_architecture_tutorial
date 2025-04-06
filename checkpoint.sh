#! /bin/bash

# take args from command line
# use "checkpoint" as a default commit message

if [ -z "$1" ]; then
    message="checkpoint"
else
    message="$1"
fi

git add .
git commit -m "$message"
git push

