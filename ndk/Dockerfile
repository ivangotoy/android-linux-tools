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

ENV ANDROID_NDK_HOME=/opt/ndk NDK_RELEASE=${NDK_RELEASE} \
    PATH=/opt/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
WORKDIR /work
