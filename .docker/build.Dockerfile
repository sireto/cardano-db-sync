ARG UBUNTU_VERSION=20.04
FROM ubuntu:${UBUNTU_VERSION}
ENV DEBIAN_FRONTEND=nonintercative
RUN mkdir -p /app/src
WORKDIR /app

# development dependencies
RUN apt-get update -y && apt-get install -y \
  automake \
  build-essential \
  g++\
  git \
  jq \
  libffi-dev \
  libghc-postgresql-libpq-dev \
  libgmp-dev \
  libncursesw5 \
  libpq-dev \
  libssl-dev \
  libsystemd-dev \
  libtinfo-dev \
  libtool \
  make \
  pkg-config \
  tmux \
  wget \
  zlib1g-dev
ARG CABAL_VERSION=3.2.0.0
ARG GHC_VERSION=8.10.5
ARG IOHK_LIBSODIUM_GIT_REV=66f017f16633f2060db25e17c170c2afa0f2a8a1

# install cabal
RUN wget --secure-protocol=TLSv1_2 \
  https://downloads.haskell.org/~cabal/cabal-install-${CABAL_VERSION}/cabal-install-${CABAL_VERSION}-x86_64-unknown-linux.tar.xz &&\
  tar -xf cabal-install-${CABAL_VERSION}-x86_64-unknown-linux.tar.xz &&\
  rm cabal-install-${CABAL_VERSION}-x86_64-unknown-linux.tar.xz cabal.sig &&\
  mv cabal /usr/local/bin/

# install ghc from sources
WORKDIR /app/ghc
RUN wget --secure-protocol=TLSv1_2 \
  https://downloads.haskell.org/~ghc/${GHC_VERSION}/ghc-${GHC_VERSION}-x86_64-deb9-linux.tar.xz &&\
  tar -xf ghc-${GHC_VERSION}-x86_64-deb9-linux.tar.xz &&\
  rm ghc-${GHC_VERSION}-x86_64-deb9-linux.tar.xz \
  && cd /app/ghc/ghc-${GHC_VERSION} \
  && ./configure && make install \
  && cd .. && rm -rf /app/ghc/ghc-${GHC_VERSION}

# install libsodium from sources with prefix '/'
WORKDIR /app/src
RUN git clone https://github.com/input-output-hk/libsodium.git &&\
  cd libsodium \
  && git fetch --all --tags &&\
  git checkout ${IOHK_LIBSODIUM_GIT_REV} \
  && ./autogen.sh && \
  ./configure --prefix= && \
  make && \
  make install  && cd .. && rm -rf ./libsodium

