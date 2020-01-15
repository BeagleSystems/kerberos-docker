FROM debian:stretch
MAINTAINER "Cédric Verstraeten" <hello@cedric.ws>

ARG APP_ENV=master
ENV APP_ENV ${APP_ENV}
ARG PHP_VERSION=7.1
ARG FFMPEG_VERSION=3.1

#################################
# Surpress Upstart errors/warning

RUN dpkg-divert --local --rename --add /sbin/initctl
RUN ln -sf /bin/true /sbin/initctl

#############################################
# Let the container know that there is no tty

ENV DEBIAN_FRONTEND noninteractive

#########################################
# Update base image
# Add sources for latest nginx and cmake
# Install software requirements

RUN apt-get update && apt-get install -y apt-transport-https wget lsb-release && \
wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg && \
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list && \
apt -y update && \
apt -y install software-properties-common libssl-dev git supervisor curl \
subversion libcurl4-gnutls-dev cmake dh-autoreconf autotools-dev autoconf automake gcc g++ \
build-essential libtool make nasm zlib1g-dev tar apt-transport-https \
ca-certificates wget nginx php${PHP_VERSION}-cli php${PHP_VERSION}-gd php${PHP_VERSION}-mcrypt php${PHP_VERSION}-curl \
php${PHP_VERSION}-mbstring php${PHP_VERSION}-dom php${PHP_VERSION}-zip php${PHP_VERSION}-fpm pwgen && \
curl -sL https://deb.nodesource.com/setup_9.x | bash - && apt-get install -y nodejs npm

RUN rm /usr/bin/gcc  && \
rm /usr/bin/g++ && \
ln -s /usr/bin/gcc-4.8 /usr/bin/gcc && \
ln -s /usr/bin/g++-4.8 /usr/bin/g++ && gcc -v

############################
# Clone and build x264

RUN git clone https://code.videolan.org/videolan/x264 /tmp/x264 && \
	cd /tmp/x264 && \
	git checkout df79067c && \
	./configure --prefix=/usr --enable-shared --enable-static --enable-pic && make && make install

############################
# Clone and build ffmpeg

RUN apt-get install -y pkg-config && git clone https://github.com/FFmpeg/FFmpeg && \
	cd FFmpeg && git checkout remotes/origin/release/${FFMPEG_VERSION} && \
	./configure --enable-gpl --enable-libx264 && make && \
    make install && \
    cd .. && rm -rf FFmpeg

############################
# Clone and build machinery

RUN git clone https://github.com/kerberos-io/machinery /tmp/machinery && \
    cd /tmp/machinery && git checkout ${APP_ENV} && \
    mkdir build && cd build && \
    cmake .. && make && make check && make install && \
    rm -rf /tmp/machinery && \
    chown -Rf www-data.www-data /etc/opt/kerberosio && \
    chmod -Rf 777 /etc/opt/kerberosio/config

#####################
# Clone and build web

RUN git clone https://github.com/kerberos-io/web /var/www/web && cd /var/www/web && git checkout ${APP_ENV} && \
chown -Rf www-data.www-data /var/www/web && curl -sSk https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer && \
cd /var/www/web && \
composer install --prefer-source && \
npm config set unsafe-perm true && \
npm config set registry http://registry.npmjs.org/ && \
npm config set strict-ssl=false && \
npm install -g bower && \
cd public && \
sed -i 's/https/http/g' .bowerrc && \
bower --allow-root install

RUN rm /var/www/web/public/capture && \
ln -s /etc/opt/kerberosio/capture/ /var/www/web/public/capture

# Fixes, because we are now combining the two docker images.
# Docker is aware of both web and machinery.
RUN sed -i -e "s/'insideDocker'/'insideDocker' => false,\/\//" /var/www/web/app/Http/Controllers/SystemController.php
# RUN sed -i -e "s/\$output \=/\$output \= '';\/\//" /var/www/web/app/Http/Controllers/SettingsController.php
RUN sed -i -e "s/service kerberosio status/supervisorctl status machinery \| grep \"RUNNING\"';\/\//" /var/www/web/app/Http/Repositories/System/OSSystem.php

###################
# nginx site conf

RUN rm -Rf /etc/nginx/conf.d/* && rm -Rf /etc/nginx/sites-available/default  && rm -Rf /etc/nginx/sites-enabled/default  && mkdir -p /etc/nginx/ssl
ADD ./web.conf /etc/nginx/sites-available/default.conf
RUN ln -s /etc/nginx/sites-available/default.conf /etc/nginx/sites-enabled/default.conf

########################################
# Force both nginx and PHP-FPM to run in the foreground
# This is a requirement for supervisor

RUN echo "daemon off;" >> /etc/nginx/nginx.conf
RUN sed -i -e "s/;daemonize\s*=\s*yes/daemonize = no/g" /etc/php/${PHP_VERSION}/fpm/php-fpm.conf
RUN sed -i 's/"GPCS"/"EGPCS"/g' /etc/php/${PHP_VERSION}/fpm/php.ini
RUN sed -i 's/"--daemonize/"--daemonize --allow-to-run-as-root/g' /etc/init.d/php${PHP_VERSION}-fpm
RUN sed -i 's/www-data/root/g' /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf
RUN sed -i 's/www-data/root/g' /etc/nginx/nginx.conf
RUN sed -i -e "s/;listen.mode = 0660/listen.mode = 0750/g" /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf && \
find /etc/php/${PHP_VERSION}/cli/conf.d/ -name "*.ini" -exec sed -i -re 's/^(\s*)#(.*)/\1;\2/g' {} \;

# Merged supervisord config of both web and machinery
ADD ./supervisord.conf /etc/supervisord.conf

# Merge the two run files.
ADD ./run.sh /run.sh
RUN chmod 755 /run.sh
RUN chmod +x /run.sh
RUN sed -i -e 's/\r$//' /run.sh

# Exposing web on port 80 and livestreaming on port 8889
EXPOSE 8889
EXPOSE 80

# Make capture and config directory visible
VOLUME ["/etc/opt/kerberosio/capture"]
VOLUME ["/etc/opt/kerberosio/config"]
VOLUME ["/etc/opt/kerberosio/logs"]

# Make web config directory visible
VOLUME ["/var/www/web/config"]

# Start runner script when booting container
CMD ["/bin/bash", "/run.sh"]
