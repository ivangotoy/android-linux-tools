VERSION=1.4.9
URL=https://www.netfilter.org/pub/conntrack-tools/conntrack-tools-$VERSION.tar.xz
SHA256=c15afe488a8d408c9d6d61e97dbd19f3c591942f62c13df6453a961ca4231cae
CHECKSUM_SOURCE="netfilter.org detached signature $URL.sig, Netfilter Core Team key 8C5F7146A1757A65E2422A94D70D1A666ACF2B21"
LICENSE=GPL-2.0-or-later
DEPS="libmnl libnfnetlink libnetfilter_conntrack libnetfilter_cttimeout libnetfilter_cthelper"
build() {
  # rpc/rpc_msg.h (libtirpc) is only used by conntrackd's RPC helper, which is not built.
  # --enable-cthelper also probes libnetfilter_queue, which only conntrackd links (nfct uses cthelper only).
  ac_cv_header_rpc_rpc_msg_h=yes LIBNETFILTER_QUEUE_CFLAGS=" " LIBNETFILTER_QUEUE_LIBS=" " \
    configure_std --enable-cthelper --enable-cttimeout --disable-systemd
  make -j"$JOBS" -C extensions
  make -j"$JOBS" -C src conntrack nfct LDFLAGS="$LT_LDFLAGS"
  install_bin src/conntrack conntrack
  install_bin src/nfct nfct
}
