# create an up-to-date base image for everything
FROM alpine:latest AS base

RUN \
  apk --no-cache --update-cache upgrade

# run-time dependencies
RUN \
  apk --no-cache add --virtual build-dependencies \
    7zip \
    bash \
    curl \
    doas \
    libcrypto3 \
    libssl3 \
    python3 \
    qt6-qtbase \
    qt6-qtbase-sqlite \
    tini \
    tzdata \
    zlib

# image for building
FROM base AS builder

ARG QBT_VERSION \
    BOOST_VERSION_MAJOR="1" \
    BOOST_VERSION_MINOR="86" \
    BOOST_VERSION_PATCH="0" \
    LIBBT_VERSION="RC_1_2" \
    LIBBT_CMAKE_FLAGS=""

# check environment variables
RUN \
  if [ -z "${QBT_VERSION}" ]; then \
    echo 'Missing QBT_VERSION variable. Check your command line arguments.' && \
    exit 1 ; \
  fi

# alpine linux packages:
# https://git.alpinelinux.org/aports/tree/community/libtorrent-rasterbar/APKBUILD
# https://git.alpinelinux.org/aports/tree/community/qbittorrent/APKBUILD
RUN \
  apk add \
    cmake \
    git \
    g++ \
    make \
    ninja \
    openssl-dev \
    qt6-qtbase-dev \
    qt6-qttools-dev \
    zlib-dev

# compiler, linker options:
# https://gcc.gnu.org/onlinedocs/gcc/Option-Summary.html
# https://gcc.gnu.org/onlinedocs/gcc/Link-Options.html
# https://sourceware.org/binutils/docs/ld/Options.html
ENV CFLAGS="-pipe -fstack-clash-protection -fstack-protector-strong -fno-plt -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3 -D_GLIBCXX_ASSERTIONS" \
    CXXFLAGS="-pipe -fstack-clash-protection -fstack-protector-strong -fno-plt -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3 -D_GLIBCXX_ASSERTIONS" \
    LDFLAGS="-gz -Wl,-O1,--as-needed,--sort-common,-z,now,-z,pack-relative-relocs,-z,relro"

# prepare boost
RUN \
  wget -O boost.tar.gz "https://archives.boost.io/release/$BOOST_VERSION_MAJOR.$BOOST_VERSION_MINOR.$BOOST_VERSION_PATCH/source/boost_${BOOST_VERSION_MAJOR}_${BOOST_VERSION_MINOR}_${BOOST_VERSION_PATCH}.tar.gz" && \
  tar -xf boost.tar.gz && \
  mv boost_* boost && \
  cd boost && \
  ./bootstrap.sh && \
  ./b2 stage --stagedir=./ --with-headers

# build libtorrent
RUN \
  git clone \
    --branch "${LIBBT_VERSION}" \
    --depth 1 \
    --recurse-submodules \
    https://github.com/arvidn/libtorrent.git && \
  cd libtorrent && \
  cmake \
    -B build \
    -G Ninja \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_CXX_STANDARD=20 \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
    -DBOOST_ROOT=/boost/lib/cmake \
    -Ddeprecated-functions=OFF \
    $LIBBT_CMAKE_FLAGS && \
  cmake --build build -j $(nproc) && \
  cmake --install build && \
  # Remove temp files
  cd && \
  apk del --purge build-dependencies && \
  rm -rf /tmp/*
