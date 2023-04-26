ecr_uri=729581434105.dkr.ecr.us-east-1.amazonaws.com/laravel-on-ecs-dzg

# for buildx
# docker buildx create --name mybuilder
# docker buildx use mybuilder

ecr_uri=729581434105.dkr.ecr.us-east-1.amazonaws.com/laravel-on-ecs-dzg

#aws ecr create-repository --repository-name laravel-on-ecs-dzg-php
aws ecr get-login-password  | docker login --username AWS --password-stdin $ecr_uri-php
sed -i -e "s/#docker-build# //" docker/php/Dockerfile
docker buildx build --platform linux/amd64,linux/arm64 -t $ecr_uri-php:latest -f docker/php/Dockerfile . --push
git checkout docker/php/Dockerfile

#aws ecr create-repository --repository-name laravel-on-ecs-dzg-nginx
aws ecr get-login-password  | docker login --username AWS --password-stdin $ecr_uri-nginx
docker buildx build --platform linux/amd64,linux/arm64 -t $ecr_uri-nginx:latest -f docker/nginx/Dockerfile docker/nginx/ --push

#aws ecr create-repository --repository-name laravel-on-ecs-dzg-proxysql
aws ecr get-login-password  | docker login --username AWS --password-stdin $ecr_uri-proxysql
docker buildx build --platform linux/amd64,linux/arm64 -t $ecr_uri-proxysql:latest -f docker/proxysql/Dockerfile docker/proxysql/ --push
