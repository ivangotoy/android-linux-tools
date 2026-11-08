VERSION=12.8.0
URL=https://sysstat.github.io/sysstat-packages/sysstat-$VERSION.tar.gz
SHA256=4625dfddb04b357bb98341a4a4897c0d939c48ee1b67ae519dcc50a951b62c70
CHECKSUM_SOURCE="SHA1 bf343509a2a5a8019e72191ed6858659b868af6e published on sysstat.github.io/versions.html (verified at pin time; it is the .tar.gz)"
LICENSE=GPL-2.0-or-later
build() {
  configure_std --disable-sensors --disable-pcp --disable-documentation --disable-stripping --disable-file-attr \
    sa_lib_dir=/data/local/lib/sa sa_dir=/data/local/var/log/sa conf_dir=/data/local/etc/sysconfig
  make -j"$JOBS" iostat pidstat mpstat
  local p
  for p in iostat pidstat mpstat; do install_bin "$p" "$p"; done
}
