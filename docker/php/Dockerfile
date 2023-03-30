FROM php:8.2-fpm

# 安装 PHP 扩展、git 和 Composer
RUN apt-get update && apt-get install -y git \
    && docker-php-ext-install pdo_mysql \
    && curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# 允许以 root 用户身份运行 Composer
ENV COMPOSER_ALLOW_SUPERUSER 1

# 安装 Laravel
RUN composer global require laravel/installer

# 将 Laravel 安装器添加到环境变量
ENV PATH="${PATH}:/root/.composer/vendor/bin"

# 设置工作目录
WORKDIR /var/www/html

# COPY
#docker-build# COPY ./laravel-app /var/www/html