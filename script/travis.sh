#!/bin/bash
set -ex

# Create git REVISION file
# Needed for finding which manifest file to use for precompiled assets
echo $TRAVIS_COMMIT > REVISION

if [ "${TRAVIS_JOB}" = "build" ]; then
  docker login -u $DOCKER_USERNAME -p $DOCKER_PASSWORD quay.io
  if docker pull quay.io/$TRAVIS_REPO_SLUG:$TRAVIS_BRANCH
  then
    docker build --cache-from quay.io/$TRAVIS_REPO_SLUG:$TRAVIS_BRANCH -t quay.io/$TRAVIS_REPO_SLUG:$TRAVIS_BRANCH .
  else
    docker pull quay.io/$TRAVIS_REPO_SLUG:master
    docker build --cache-from quay.io/$TRAVIS_REPO_SLUG:master -t quay.io/$TRAVIS_REPO_SLUG:$TRAVIS_BRANCH .
  fi
  docker tag quay.io/$TRAVIS_REPO_SLUG:$TRAVIS_BRANCH quay.io/$TRAVIS_REPO_SLUG:${TRAVIS_COMMIT::8}
  docker tag quay.io/$TRAVIS_REPO_SLUG:${TRAVIS_COMMIT::8} quay.io/$TRAVIS_REPO_SLUG:travis-$TRAVIS_BUILD_NUMBER
  docker push quay.io/$TRAVIS_REPO_SLUG

fi
