# Copyright 2017-2017 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Amazon Software License (the "License"). You may not use this file except in compliance with the License.
# A copy of the License is located at
#
#    http://aws.amazon.com/asl/
#
# or in the "license" file accompanying this file.
# This file is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, express or implied.
# See the License for the specific language governing permissions and limitations under the License.
#

FROM ubuntu:14.04.5

# Building git from source code:
#   Ubuntu's default git package is built with broken gnutls. Rebuild git with openssl.
##########################################################################
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       wget python python2.7-dev fakeroot ca-certificates tar gzip zip \
       autoconf automake bzip2 file g++ gcc imagemagick libbz2-dev libc6-dev libcurl4-openssl-dev \
       libdb-dev libevent-dev libffi-dev libgeoip-dev libglib2.0-dev libjpeg-dev libkrb5-dev \
       liblzma-dev libmagickcore-dev libmagickwand-dev libmysqlclient-dev libncurses-dev libpng-dev \
       libpq-dev libreadline-dev libsqlite3-dev libssl-dev libtool libwebp-dev libxml2-dev libxslt-dev \
       libyaml-dev make patch xz-utils zlib1g-dev unzip curl \
    && apt-get -qy build-dep git \
    && apt-get -qy install libcurl4-openssl-dev git-man liberror-perl \
    && mkdir -p /usr/src/git-openssl \
    && cd /usr/src/git-openssl \
    && apt-get source git \
    && cd $(find -mindepth 1 -maxdepth 1 -type d -name "git-*") \
    && sed -i -- 's/libcurl4-gnutls-dev/libcurl4-openssl-dev/' ./debian/control \
    && sed -i -- '/TEST\s*=\s*test/d' ./debian/rules \
    && dpkg-buildpackage -rfakeroot -b \
    && find .. -type f -name "git_*ubuntu*.deb" -exec dpkg -i \{\} \; \
    && rm -rf /usr/src/git-openssl \
# Install dependencies by all python images equivalent to buildpack-deps:jessie
# on the public repos.
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

RUN wget "https://bootstrap.pypa.io/get-pip.py" -O /tmp/get-pip.py \
    && python /tmp/get-pip.py \
    && pip install awscli==1.11.25 \
    && rm -fr /var/lib/apt/lists/* /tmp/* /var/tmp/*


ENV DOCKER_BUCKET="get.docker.com" \
    DOCKER_VERSION="1.12.1" \
    DOCKER_SHA256="05ceec7fd937e1416e5dce12b0b6e1c655907d349d52574319a1e875077ccb79" \
    DIND_COMMIT="3b5fac462d21ca164b3778647420016315289034"


ENV DOCKER_CHANNEL stable
ENV DOCKER_VERSION 17.09.0-ce
ENV DOCKER_API_VERSION 1.27
#RUN curl -fsSL "https://download.docker.com/linux/static/${DOCKER_CHANNEL}/x86_64/docker-${DOCKER_VERSION}.tgz" -o docker.tgz \
#  | tar -xzC /usr/local/bin --strip=1 docker/docker
#COPY dockerd-entrypoint.sh /usr/local/bin/

# From the docker:1.11
RUN set -x \
    && curl -fsSL "https://download.docker.com/linux/static/${DOCKER_CHANNEL}/x86_64/docker-${DOCKER_VERSION}.tgz" -o docker.tgz \
    && tar -xzvf docker.tgz \
    && mv docker/* /usr/local/bin/ \
    && rmdir docker \
    && rm docker.tgz \
    && docker -v \
# From the docker dind 1.11
    && apt-get update && apt-get install -y --no-install-recommends \
       e2fsprogs iptables xfsprogs xz-utils \
# set up subuid/subgid so that "--userns-remap=default" works out-of-the-box
    && addgroup dockremap \
    && useradd -g dockremap dockremap \
    && echo 'dockremap:165536:65536' >> /etc/subuid \
    && echo 'dockremap:165536:65536' >> /etc/subgid \
    && wget "https://raw.githubusercontent.com/docker/docker/${DIND_COMMIT}/hack/dind" -O /usr/local/bin/dind \
    && chmod +x /usr/local/bin/dind \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Java
RUN apt-get update \
    && apt-get install -y software-properties-common \
    && add-apt-repository -y ppa:openjdk-r/ppa \
    && apt-get update \
    && apt-get install -y openjdk-8-jdk \
    && apt-get install -y ant \
    && apt-get clean \
    && apt-get update \
    && apt-get install ca-certificates-java \
    && apt-get clean \
    && update-ca-certificates -f \
    && export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64

# Ruby
RUN apt-get update \
    && apt-get install -y software-properties-common \
    && sudo apt-get -y install software-properties-common python-software-properties \
    && sudo apt-add-repository ppa:brightbox/ruby-ng \
    && sudo apt-get update \
    && sudo apt-get install build-essential libssl-dev \
    && sudo apt-get install -y curl gnupg ruby2.2 ruby2.2-dev \
    && gem install bundler --no-rdoc --no-ri

# Postgres
RUN apt-get update \
    && apt-get install -y software-properties-common \
    && wget -q https://www.postgresql.org/media/keys/ACCC4CF8.asc -O - | sudo apt-key add - \
    && sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ `lsb_release -cs`-pgdg main" >> /etc/apt/sources.list.d/pgdg.list' \
    && apt-get update \
    && sudo apt-get install -y postgresql postgresql-contrib \
    && truncate -s 0 /etc/postgresql/10/main/pg_hba.conf \
    && echo "host all all ::1/128 trust" >> /etc/postgresql/10/main/pg_hba.conf \
    && echo "local   all             all                         trust" >> /etc/postgresql/10/main/pg_hba.conf \
    && echo "host all  all    0.0.0.0/0  trust" >> /etc/postgresql/10/main/pg_hba.conf \
    && echo "listen_addresses='*'" >> /etc/postgresql/10/main/postgresql.conf

RUN /etc/init.d/postgresql start \
    && psql -h localhost -U postgres --command "CREATE ROLE topsteptrader WITH login SUPERUSER ENCRYPTED PASSWORD 'topsteptrader';" \
    && psql -h localhost -U postgres --command "CREATE DATABASE topsteptrader_development WITH OWNER topsteptrader;" \
    && psql -h localhost -U postgres --command "CREATE DATABASE topsteptrader_test WITH OWNER topsteptrader;"

# Node / npm
ENV NODE_VERSION_FOR_APP=v6.9.1 \
    NODE_VERSION_FOR_PROTRACTOR=v8.9.1 \
    NVM_DIR=/home/node/.nvm

RUN curl https://raw.githubusercontent.com/creationix/nvm/v0.33.1/install.sh | bash

RUN . $NVM_DIR/nvm.sh && nvm install $NODE_VERSION_FOR_APP && nvm alias default $NODE_VERSION_FOR_APP \
    . $NVM_DIR/nvm.sh && nvm install $NODE_VERSION_FOR_PROTRACTOR \
    . $NVM_DIR/nvm.sh && nvm ls

# Yarn
RUN . $NVM_DIR/nvm.sh && npm install -g yarn

# docker-compose
RUN curl -L https://github.com/docker/compose/releases/download/1.17.0/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
RUN chmod +x /usr/local/bin/docker-compose

## docker
#RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
#RUN sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
#RUN sudo apt-get install apt-transport-https \
#    && sudo apt-get update \
#    && apt-cache policy docker-ce \
#    && sudo apt-get install -y docker-ce=17.09.0~ce-0~ubuntu

# Chrome
RUN echo "deb http://dl.google.com/linux/chrome/deb/ stable main" | sudo tee -a /etc/apt/sources.list
RUN wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | sudo apt-key add -
RUN sudo sh -c 'echo "deb http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list' \
    && sudo apt-get update \
    && sudo apt-get install -y google-chrome-stable \
    && sudo apt-get install -f


VOLUME /var/lib/docker

ENTRYPOINT ["dockerd-entrypoint.sh"]
#