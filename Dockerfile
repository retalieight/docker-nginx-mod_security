FROM ubuntu:18.04

ENV NGINX_VERSION 1.20.2

EXPOSE 80

RUN apt-get update && apt-get upgrade -y && apt-get install bison build-essential ca-certificates curl dh-autoreconf doxygen \
    flex gawk git iputils-ping libcurl4-gnutls-dev libexpat1-dev libgeoip-dev liblmdb-dev \
    libpcre3-dev libpcre++-dev libssl-dev libtool libxml2 libxml2-dev libyajl-dev locales \
    liblua5.3-dev pkg-config wget zlib1g-dev zlibc libxslt1.1 libgd-dev -y

# Get nginx source.
RUN cd /opt && wget https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz \
  && tar zxf nginx-${NGINX_VERSION}.tar.gz \
  && rm nginx-${NGINX_VERSION}.tar.gz

# Get mod_security module.
RUN cd /opt && git clone https://github.com/SpiderLabs/ModSecurity && cd ModSecurity \
  && git submodule init && git submodule update && ./build.sh && ./configure && make -j $(nproc) && make install

RUN cd /opt && git clone --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git && mkdir -p /usr/local/nginx/modules && mkdir -p /usr/local/nginx/modsec

# Compile nginx with mod_security.
RUN cd /opt/nginx-${NGINX_VERSION} \
  && ./configure \
  --prefix=/usr/local/nginx \
  --add-dynamic-module=../ModSecurity-nginx \
  --conf-path=/usr/local/nginx/conf/nginx.conf \
  --with-file-aio \
  --error-log-path=/opt/nginx/logs/error.log \
  --http-log-path=/opt/nginx/logs/access.log \
  --with-threads \
  --with-cc-opt="-O3" \
  --with-debug
RUN cd /opt/nginx-${NGINX_VERSION} && make modules && cp objs/ngx_http_modsecurity_module.so /usr/local/nginx/modules && make -j $(nproc) && make install

RUN rm -rf /var/cache/* /tmp/*

RUN git clone https://github.com/coreruleset/coreruleset /usr/local/modsecurity-crs && mv /usr/local/modsecurity-crs/crs-setup.conf.example /usr/local/modsecurity-crs/crs-setup.conf && mv /usr/local/modsecurity-crs/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf.example /usr/local/modsecurity-crs/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf && cp /opt/ModSecurity/unicode.mapping /usr/local/nginx/modsec && cp /opt/ModSecurity/modsecurity.conf-recommended /usr/local/nginx/modsec/modsecurity.conf

RUN sed -i 's/SecRuleEngine.*/SecRuleEngine On/g' /usr/local/nginx/modsec/modsecurity.conf && touch /usr/local/nginx/modsec/main.conf && echo 'Include /usr/local/nginx/modsec/modsecurity.conf' > /usr/local/nginx/modsec/main.conf && echo 'Include /usr/local/modsecurity-crs/crs-setup.conf' >> /usr/local/nginx/modsec/main.conf && echo 'Include /usr/local/modsecurity-crs/rules/*.conf' >> /usr/local/nginx/modsec/main.conf

RUN rm -f /usr/local/nginx/conf/nginx.conf
COPY nginx.conf /usr/local/nginx/conf/nginx.conf
RUN mkdir -p /usr/local/nginx/sites-enabled/ && ln -s /usr/local/nginx/sites-available/default /usr/local/nginx/sites-enabled/default
COPY default /usr/local/nginx/sites-available/default

CMD /usr/local/nginx/sbin/nginx -g 'daemon off;'
