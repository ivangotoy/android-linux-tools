# android-linux-tools v2 builder: Android NDK (bionic) cross toolchain in a pinned Debian image.
# Base image pinned by digest; Debian packages pinned to a snapshot.debian.org date; NDK pinned by
# release and verified against the SHA-1 Google publishes (developer.android.com/ndk/downloads and
# dl.google.com/android/repository/repository2-3.xml) plus a SHA-256 recorded at pin time.
FROM debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2

ARG DEBIAN_SNAPSHOT=20261101T000000Z
ARG NDK_RELEASE=r30
ARG NDK_SIZE=738633529
ARG NDK_SHA1=5107f898313790e449e87eee2183d9a20602dee9
ARG NDK_SHA256=753611f410d002cfcd3f3dc2ef49aad532089d3180b436c060a90bf0fcb64df2

ENV DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8 TZ=UTC

RUN rm -f /etc/apt/sources.list.d/debian.sources \
 && printf '%s\n' \
    "deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT} trixie main" \
    "deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT} trixie-updates main" \
    "deb [check-valid-until=no] http://snapshot.debian.org/archive/debian-security/${DEBIAN_SNAPSHOT} trixie-security main" \
    > /etc/apt/sources.list \
 && apt-get -o Acquire::Retries=5 update \
 && apt-get -o Acquire::Retries=5 install -y --no-install-recommends \
    ca-certificates curl unzip zip xz-utils bzip2 lzip zstd patch file \
    make cmake ninja-build meson autoconf automake libtool pkgconf autopoint gettext \
    bison flex gperf m4 perl python3 gcc libc6-dev binutils patchelf texinfo groff-base \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL --retry 5 -o /opt/ndk.zip "https://dl.google.com/android/repository/android-ndk-${NDK_RELEASE}-linux.zip" \
 && test "$(stat -c %s /opt/ndk.zip)" = "${NDK_SIZE}" \
 && echo "${NDK_SHA1}  /opt/ndk.zip" | sha1sum -c - \
 && echo "${NDK_SHA256}  /opt/ndk.zip" | sha256sum -c - \
 && cd /opt && unzip -q ndk.zip && rm ndk.zip && mv "android-ndk-${NDK_RELEASE}" ndk \
 && test -x /opt/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/clang

# Host C++ compiler for LLVM's native tablegen tools (llvm recipe) and xxd for bpftrace's embedded stdlib.
# A separate layer after the NDK, from the same snapshot, so the layers above stay unchanged.
RUN apt-get -o Acquire::Retries=5 update \
 && apt-get -o Acquire::Retries=5 install -y --no-install-recommends g++ xxd \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# Go toolchain for eCapture (cgo links with the NDK clang). Pinned by release, size and the SHA-256 Google
# publishes (go.dev/dl/?mode=json); the detached signature <tarball URL>.asc (Google Linux Packages Signing
# Authority, EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796) was verified at pin time. A separate layer after the ones
# above, so they stay unchanged.
ARG GO_VERSION=1.27.3
ARG GO_SIZE=70588678
ARG GO_SHA256=65efbc80fdc1fa2cd2631cad5b481777a68e8725f34e89f50fc6ac714e379b40
RUN curl -fsSL --retry 5 -o /opt/go.tar.gz "https://dl.google.com/go/go${GO_VERSION}.linux-amd64.tar.gz" \
 && test "$(stat -c %s /opt/go.tar.gz)" = "${GO_SIZE}" \
 && echo "${GO_SHA256}  /opt/go.tar.gz" | sha256sum -c - \
 && tar -xzf /opt/go.tar.gz -C /opt --no-same-owner && rm /opt/go.tar.gz \
 && test "$(/opt/go/bin/go env GOVERSION)" = "go${GO_VERSION}"

# bc for `make prepare` of the kernel headers that eCapture's non-CO-RE BPF objects are compiled against.
# Debian trixie bc 1.07.1-4 from the same snapshot, fetched by its content address (snapshot.debian.org/file/<sha1>)
# and checked against the SHA-256 of the snapshot's Packages index; apt installs it with its dependency.
ARG BC_DEB=bc_1.07.1-4_amd64.deb
ARG BC_SHA1=3a6da630d418b7d971f0025c0a1e00ccb4375843
ARG BC_SHA256=d055a11f0f9c5f8fe78b31d502c01dfe46ddf9c24f753aaddadaaff95fcc75ad
RUN curl -fsSL --retry 5 -o "/opt/${BC_DEB}" "http://snapshot.debian.org/file/${BC_SHA1}/${BC_DEB}" \
 && echo "${BC_SHA256}  /opt/${BC_DEB}" | sha256sum -c - \
 && apt-get -o Acquire::Retries=5 update \
 && apt-get -o Acquire::Retries=5 install -y --no-install-recommends "/opt/${BC_DEB}" \
 && apt-get clean && rm -rf /var/lib/apt/lists/* "/opt/${BC_DEB}" \
 && test "$(echo 2^10 | bc)" = 1024

ENV ANDROID_NDK_HOME=/opt/ndk NDK_RELEASE=${NDK_RELEASE} GOTOOLCHAIN=local GOTELEMETRY=off \
    PATH=/opt/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin:/opt/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
WORKDIR /work
