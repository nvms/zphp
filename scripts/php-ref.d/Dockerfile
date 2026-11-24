# the reference php for the local compat harnesses (scripts/php-ref): php's
# official cli image of the target release plus the extensions the suites
# touch, which the image leaves out. build arg PHP_VERSION is
# src/php_version.zig's version
ARG PHP_VERSION=8.6.0
FROM php:${PHP_VERSION}-cli
RUN apt-get update && apt-get install -y --no-install-recommends \
        $PHPIZE_DEPS libargon2-dev libcurl4-openssl-dev libreadline-dev libsodium-dev \
        libsqlite3-dev libssl-dev zlib1g-dev \
        libgmp-dev libicu-dev libonig-dev libzip-dev libpng-dev libjpeg-dev \
        libwebp-dev libavif-dev libfreetype-dev libxpm-dev libldap2-dev libxml2-dev \
        libxslt1-dev libpq-dev libbz2-dev unzip git locales netbase \
    && rm -rf /var/lib/apt/lists/*
# the 8.6 images are built thread safe (--enable-zts --disable-zend-signals);
# the php the suites compare against (setup-php, distribution packages, the
# 8.5 images) is not, which PHP_ZTS and ZEND_THREAD_SAFE show. rebuild php
# itself with the image's other configure flags
RUN set -eux; \
    flags="$(php -i | sed -n "s/^Configure Command =>  //p" | tr -d "'" \
        | sed -e 's/--enable-zts//' -e 's/--disable-zend-signals//' -e 's/build_alias=[^ ]*//' \
              -e 's/PHP_UNAME=.*//')"; \
    docker-php-source extract; \
    cd /usr/src/php; \
    eval "set -- $flags"; shift; \
    CFLAGS="$PHP_CFLAGS" CPPFLAGS="$PHP_CPPFLAGS" LDFLAGS="$PHP_LDFLAGS" \
        ./configure "$@" 'PHP_UNAME=Linux - Docker' \
        'PHP_BUILD_PROVIDER=https://github.com/docker-library/php'; \
    make -j"$(nproc)"; \
    find /usr/local/lib/php/extensions -mindepth 1 -maxdepth 1 -exec rm -rf {} +; \
    make install; \
    docker-php-ext-enable sodium; \
    make clean; \
    cd /; docker-php-source delete; \
    php -r 'exit(PHP_ZTS ? 1 : 0);'
RUN docker-php-ext-configure gd --with-jpeg --with-webp --with-avif --with-freetype --with-xpm \
    && docker-php-ext-install -j"$(nproc)" bcmath bz2 calendar exif ftp gd gettext gmp \
        intl ldap mbstring mysqli pcntl pdo_mysql pdo_pgsql pgsql shmop soap sockets \
        sysvmsg sysvsem sysvshm xsl zip
# what the host's php sees: /etc/services and protocols, and the en_*
# locales ubuntu installs
RUN sed -i 's/^# *\(en_[A-Z][A-Z]\(\.UTF-8\)\? \)/\1/' /etc/locale.gen && locale-gen
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer
# the ini the other references run with: php.ini-production plus setup-php's
# memory_limit and date.timezone
RUN cp /usr/local/etc/php/php.ini-production /usr/local/etc/php/php.ini \
    && printf 'memory_limit = -1\ndate.timezone = UTC\n' > /usr/local/etc/php/conf.d/zz-reference.ini
