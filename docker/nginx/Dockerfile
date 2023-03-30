FROM nginx:latest

# 删除默认配置
RUN rm /etc/nginx/conf.d/default.conf

# 添加自定义 Nginx 配置文件
COPY nginx.conf /etc/nginx/conf.d

