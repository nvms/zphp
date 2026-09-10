#!/bin/sh
# builds the libraries a fully static musl zphp needs that alpine either ships
# only as gcc lto archives, which lld cannot read (gmp, nghttp2, brotli,
# libpsl), or with dependencies that have no static archive at all (gd drags
# in x11/tiff/avif, openldap drags cyrus-sasl into gssapi/gdbm). everything
# is pinned, checksummed, and installed under /usr/local
set -eu

PREFIX=/usr/local
WORK="${TMPDIR:-/tmp}/zphp-static-deps"
JOBS="$(nproc)"
HOST="$(uname -m)-alpine-linux-musl"
mkdir -p "$WORK"

MANIFEST="$PREFIX/share/zphp-static-deps.txt"
mkdir -p "$PREFIX/share" && : > "$MANIFEST"

fetch() {
  name="$1"; url="$2"; sha="$3"
  echo "$name" >> "$MANIFEST"
  file="$WORK/$name"
  [ -f "$file" ] || curl -sSL --retry 3 -o "$file" "$url"
  echo "$sha  $file" | sha256sum -c - >/dev/null
  rm -rf "$WORK/src" && mkdir "$WORK/src"
  tar -xf "$file" -C "$WORK/src" --strip-components=1
  cd "$WORK/src"
}

log() { printf '%s\n' "==> $1"; }

log gmp
fetch gmp-6.3.0.tar.xz https://mirrors.kernel.org/gnu/gmp/gmp-6.3.0.tar.xz \
  a3c2b80201b89e68616f4ad30bc66aee4927c3ce50e33929ca819d5c43538898
case "$(uname -m)" in x86_64) fat=--enable-fat ;; *) fat= ;; esac
./configure --prefix="$PREFIX" --host="$HOST" --disable-shared --enable-static $fat >/dev/null
make -j"$JOBS" >/dev/null
make install >/dev/null

log nghttp2
fetch nghttp2-1.66.0.tar.xz https://github.com/nghttp2/nghttp2/releases/download/v1.66.0/nghttp2-1.66.0.tar.xz \
  00ba1bdf0ba2c74b2a4fe6c8b1069dc9d82f82608af24442d430df97c6f9e631
./configure --prefix="$PREFIX" --enable-lib-only --disable-shared --enable-static >/dev/null
make -j"$JOBS" >/dev/null
make install >/dev/null

log brotli
fetch brotli-1.1.0.tar.gz https://github.com/google/brotli/archive/refs/tags/v1.1.0.tar.gz \
  e720a6ca29428b803f4ad165371771f5398faba397edf6778837a18599ea13ff
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_INSTALL_LIBDIR=lib >/dev/null
cmake --build build -j"$JOBS" >/dev/null
cmake --install build >/dev/null

log libpsl
fetch libpsl-0.21.5.tar.gz https://github.com/rockdaboot/libpsl/releases/download/0.21.5/libpsl-0.21.5.tar.gz \
  1dcc9ceae8b128f3c0b3f654decd0e1e891afc6ff81098f227ef260449dae208
./configure --prefix="$PREFIX" --disable-shared --enable-static --enable-builtin --enable-runtime=libidn2 \
  --disable-man --disable-gtk-doc >/dev/null
make -j"$JOBS" >/dev/null
make install >/dev/null

log libgd
fetch libgd-2.3.3.tar.xz https://github.com/libgd/libgd/releases/download/gd-2.3.3/libgd-2.3.3.tar.xz \
  3fe822ece20796060af63b7c60acb151e5844204d289da0ce08f8fdf131e5a61
./configure --prefix="$PREFIX" --disable-shared --enable-static \
  --with-png --with-jpeg --with-freetype \
  --without-fontconfig --without-raqm --without-liq --without-xpm --without-x \
  --without-tiff --without-webp --without-heif --without-avif >/dev/null
make -j"$JOBS" >/dev/null
make install >/dev/null

log openldap
fetch openldap-2.6.10.tgz https://www.openldap.org/software/download/OpenLDAP/openldap-release/openldap-2.6.10.tgz \
  c065f04aad42737aebd60b2fe4939704ac844266bc0aeaa1609f0cad987be516
./configure --prefix="$PREFIX" --disable-slapd --disable-shared --enable-static \
  --without-cyrus-sasl --with-tls=openssl --disable-debug >/dev/null
make depend >/dev/null
for d in include libraries; do make -C "$d" -j"$JOBS" >/dev/null; make -C "$d" install >/dev/null; done

log done
ls "$PREFIX"/lib/*.a
