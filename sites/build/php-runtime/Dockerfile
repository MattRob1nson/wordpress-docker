ARG PHP_VERSION

FROM php:$PHP_VERSION
RUN apt-get update
RUN apt-get --assume-yes install wget
RUN apt-get --assume-yes install libpng-dev
RUN cd /tmp
RUN wget http://downloads3.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz
RUN tar xfz ioncube_loaders_lin_x86-64.tar.gz
RUN mv ioncube/ioncube_loader_lin_7.1.so `php-config --extension-dir`
RUN rm ioncube_loaders_lin_x86-64.tar.gz
RUN rm -rf ioncube
RUN chown root:staff `php-config --extension-dir`/ioncube_loader_lin_7.1.so
RUN docker-php-ext-install pdo pdo_mysql mysqli gd
RUN docker-php-ext-enable mysqli
RUN chown -R www-data:www-data /var/www
COPY ./conf/php.ini /usr/local/etc/php/php.ini
COPY ./conf/uploads.ini /usr/local/etc/php/conf.d/uploads.ini
