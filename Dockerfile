FROM ubuntu:16.04

ENV OTRS_VERSION=5.0.36 \
    ITSM_VERSION=5.0.36 \
    FAQ_VERSION=5.0.22 \
    SURVEY_VERSION=5.0.13 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 

SHELL ["/bin/bash", "-c"]

# Language
RUN apt-get update && apt-get install -y locales && rm -rf /var/lib/apt/lists/* \
    && echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen \
    && echo "pt_BR.UTF-8 UTF-8" >> /etc/locale.gen \
    && locale-gen \
    && update-locale LANG=${LANG}

# Packages
RUN apt-get update \
    && apt-get install -y \
        apache2 \
        bash-completion \
        build-essential \
        cron \
        curl \
        gettext \
        git-core \
        graphviz \
        libapache2-mod-perl2 \
        libarchive-zip-perl \
        libauthen-ntlm-perl \
        libauthen-sasl-perl \
        libcrypt-eksblowfish-perl \
        libcrypt-ssleay-perl \
        libdatetime-perl \
        libdbd-mysql-perl \
        libdbd-odbc-perl \
        libdbd-pg-perl \
        libdbi-perl \
        libencode-hanextra-perl \
        libexpat1-dev \
        libgdbm3 \
        libgraphviz-perl \
        libio-socket-ssl-perl \
        libjson-xs-perl \
        libmail-imapclient-perl \
        libnet-dns-perl \
        libnet-ldap-perl \
        libssl-dev \
        libswitch-perl \
        libtemplate-perl \
        libterm-readline-perl-perl \
        libtext-csv-xs-perl \
        libtimedate-perl \
        libxml-libxml-perl \
        libxml-libxslt-perl \
        libxml-parser-perl \
        libxml2-utils \
        libyaml-libyaml-perl \
        mysql-client \
        perl \
        postgresql-client \
        sendmail \
        ssh \
        sudo \
        supervisor \
        tzdata \
        unzip \
        vim \
        zip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* 

# Extra perl modules
RUN curl --silent -L https://cpanmin.us | perl - --sudo App::cpanminus \
    && cpanm --sudo --quiet --notest \ 
            Cache::Memcached::Fast \
            HTTP::Server::Brick \
            Plack \
            Search::Elasticsearch


# OTRS code
RUN mkdir /opt/otrs \
    && cd /opt \
    && curl --silent -O https://ftp.otrs.org/pub/otrs/otrs-latest-${OTRS_VERSION%.*}.tar.gz \
    && tar zxpf otrs-latest-${OTRS_VERSION%.*}.tar.gz -C /opt/otrs --strip-components=1 \
    && rm -rf otrs-latest-${OTRS_VERSION%.*}.tar.gz \
    && mkdir -p /opt/otrs/var/article \ 
                /opt/otrs/var/spool \
                /opt/otrs/var/tmp \
                /app-packages \
    && cd /app-packages \
    && curl --silent -O https://ftp.otrs.org/pub/otrs/itsm/bundle${OTRS_VERSION:0:1}/ITSM-${ITSM_VERSION}.opm \
    && curl --silent -O https://ftp.otrs.org/pub/otrs/packages/FAQ-${FAQ_VERSION}.opm \
    && curl --silent -O https://ftp.otrs.org/pub/otrs/packages/Survey-${SURVEY_VERSION}.opm

WORKDIR /opt/otrs

# include files
COPY Config.pm /opt/otrs/Kernel/Config.pm
COPY app-env.conf /etc/apache2/conf-available/app-env.conf
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY app-init.sh /app-init.sh
COPY app-run.sh /app-run.sh
COPY init-screen/* /var/www/html/
COPY .my.cnf /root/
COPY .my.cnf /opt/otrs/

# post configuration
RUN ln -s /opt/otrs/scripts/apache2-httpd.include.conf /etc/apache2/conf-available/otrs.conf \
    && a2enconf otrs \
    && a2dismod mpm_event \
    && a2enmod mpm_prefork \
    && a2enmod headers \
    && a2enmod perl \
    && a2enconf app-env \
    && sed -i -e "s/${OTRS_VERSION%.*}.x git/${OTRS_VERSION}/g" /opt/otrs/RELEASE \
    && mv var/cron/aaa_base.dist var/cron/aaa_base \
    && mv var/cron/otrs_daemon.dist var/cron/otrs_daemon \
    && echo "0 2 * * * $HOME/scripts/backup.pl -d /app-backups -r 15" > var/cron/app-backups.dist \
    && sed -i 's|$HOME/bin/otrs.Daemon.pl|. /etc/profile.d/app-env.sh; $HOME/bin/otrs.Daemon.pl|' var/cron/otrs_daemon \
    && useradd -d /opt/otrs -c 'OTRS user' -s /bin/bash otrs \
    && usermod -a -G www-data otrs \
    && usermod -a -G otrs www-data \
    && usermod -a -G tty www-data \
    && echo "PATH=\"$PATH:/opt/otrs/bin\"" > /etc/environment \
    && echo ". /etc/environment" > /opt/otrs/.profile \
    && bin/otrs.SetPermissions.pl --web-group=www-data \
    && bin/Cron.sh start otrs \
    && mkdir -p /var/log/supervisor \
    && chmod +x /*.sh \
    && mkdir /app-init.d/ \
    && mkdir /app-backups/ \
    && chown otrs:www-data /app-backups /var/www/html/* \
    && ln -sf /dev/stdout /var/log/apache2/access.log \
    && ln -sf /dev/stdout /var/log/apache2/error.log \
    && curl --silent https://github.com/OTRS/otrs/commit/f2f1ebf9fb196dafb1a3252f93bed6c1c784940b.diff > /tmp/no-sslglue.diff \
    && patch -p1 < /tmp/no-sslglue.diff \
    && rm /tmp/no-sslglue.diff


EXPOSE 80

CMD /app-run.sh
