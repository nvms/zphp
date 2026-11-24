# the reference php for the local compat harnesses (scripts/php-ref): php's
# official cli image of the target release plus the extensions the suites
# touch, which the image leaves out. build arg PHP_VERSION is
# src/php_version.zig's version
ARG PHP_VERSION=8.6.0
FROM php:${PHP_VERSION}-cli
RUN apt-get update && apt-get install -y --no-install-recommends \
        libgmp-dev libicu-dev libonig-dev libzip-dev libpng-dev libjpeg-dev \
        libwebp-dev libavif-dev libfreetype-dev libxpm-dev libldap2-dev libxml2-dev \
        libxslt1-dev libpq-dev libbz2-dev unzip git \
    && docker-php-ext-configure gd --with-jpeg --with-webp --with-avif --with-freetype --with-xpm \
    && docker-php-ext-install -j"$(nproc)" bcmath bz2 calendar exif ftp gd gettext gmp \
        intl ldap mbstring mysqli pcntl pdo_mysql pdo_pgsql pgsql shmop soap sockets \
        sysvmsg sysvsem sysvshm xsl zip \
    && rm -rf /var/lib/apt/lists/*
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer
# the ini the other references run with: php.ini-production plus setup-php's
# memory_limit and date.timezone
RUN cp /usr/local/etc/php/php.ini-production /usr/local/etc/php/php.ini \
    && printf 'memory_limit = -1\ndate.timezone = UTC\n' > /usr/local/etc/php/conf.d/zz-reference.ini
