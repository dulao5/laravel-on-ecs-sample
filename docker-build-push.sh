#aws ecr create-repository --repository-name laravel-on-ecs-dzg-php
aws ecr get-login-password  | docker login --username AWS --password-stdin $ecr_uri-php
docker build -t laravel-on-ecs-dzg-php -f docker/php/Dockerfile .
docker tag laravel-on-ecs-dzg-php:latest $ecr_uri-php:latest
docker push $ecr_uri-php:latest

#aws ecr create-repository --repository-name laravel-on-ecs-dzg-nginx
aws ecr get-login-password  | docker login --username AWS --password-stdin $ecr_uri-nginx
docker build -t laravel-on-ecs-dzg-nginx -f docker/nginx/Dockerfile docker/nginx/
docker tag laravel-on-ecs-dzg-nginx:latest $ecr_uri-nginx:latest
docker push $ecr_uri-nginx:latest
