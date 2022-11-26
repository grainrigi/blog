FROM nginx:1-alpine

COPY /public/ /usr/share/nginx/html/
RUN ln -s ../index.json /usr/share/nginx/html/ja/index.json