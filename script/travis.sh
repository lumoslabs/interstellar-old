#!/bin/bash
set -ex

# Create git REVISION file
# Needed for finding which manifest file to use for precompiled assets
echo $TRAVIS_COMMIT > REVISION

if [ "${TRAVIS_JOB}" = "build" ]; then
  # without caching. It doesn't save any time here, because this app is so simple
  docker login -u $DOCKER_USERNAME -p $DOCKER_PASSWORD quay.io
  docker build -t quay.io/$TRAVIS_REPO_SLUG:$TRAVIS_BRANCH .
  docker tag quay.io/$TRAVIS_REPO_SLUG:$TRAVIS_BRANCH quay.io/$TRAVIS_REPO_SLUG:${TRAVIS_COMMIT::8}
  docker tag quay.io/$TRAVIS_REPO_SLUG:${TRAVIS_COMMIT::8} quay.io/$TRAVIS_REPO_SLUG:travis-$TRAVIS_BUILD_NUMBER
  docker push quay.io/$TRAVIS_REPO_SLUG
fi
