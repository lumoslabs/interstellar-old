from ruby:2.5-stretch

# install python and gsutil... This can go away if we use google-cloud-storage from ruby, but ... we're not yet
# from https://github.com/dockerfile/python/blob/master/Dockerfile
RUN export CLOUD_SDK_REPO="cloud-sdk-stretch" && \
  echo "deb http://packages.cloud.google.com/apt $CLOUD_SDK_REPO main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && \
  curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -

RUN apt-get update && \
  apt-get install -y python python-dev python-pip python-virtualenv google-cloud-sdk && \
  rm -rf /var/lib/apt/lists/*

# throw errors if Gemfile has been modified since Gemfile.lock
RUN bundle config --global frozen 1

WORKDIR /usr/src/app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

CMD ["ls"]
