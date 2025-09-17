# srcs/requirements/wordpress/Dockerfile
FROM alpine:3.19

# php-fpm + needed extensions + tools
RUN apk add --no-cache \
  php82 php82-fpm php82-opcache php82-mysqli php82-json php82-session php82-curl \
  php82-dom php82-xml php82-xmlwriter php82-zip php82-mbstring php82-gd php82-phar \
  php82-iconv php82-tokenizer php82-pecl-redis \
  php82-cli curl tar bash ca-certificates

# Symlink php -> php82
RUN ln -sf /usr/bin/php82 /usr/bin/php && php -v

# web root
RUN mkdir -p /var/www/html && chown -R nobody:nogroup /var/www/html

# php-fpm pool config
COPY conf/www.conf /etc/php82/php-fpm.d/www.conf

# setup script (downloads/configures WordPress and users)
COPY tools/setup.sh /usr/local/bin/setup.sh
RUN chmod +x /usr/local/bin/setup.sh

WORKDIR /var/www/html
EXPOSE 9000
CMD ["/usr/local/bin/setup.sh"]
