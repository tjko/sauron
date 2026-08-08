FROM debian:trixie-slim AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq \
	&& apt-get install -y --no-install-recommends \
		gcc \
		libc6-dev \
		make \
		perl \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR /src

COPY . .

RUN set -eux; \
	./configure; \
	make install; \
	mkdir -p /usr/local/sauron/logs /usr/local/sauron/tmp; \
	# Source CGI/CLIs still carry -I/opt/sauron in some shebangs; normalize.
	# (matches one or more spaces between perl and -I, e.g. generatehosts)
	find /usr/local/sauron -type f -print0 \
		| xargs -0r grep -lE '^#!/usr/bin/perl +-I/opt/sauron' \
		| xargs -r sed -i -E 's|^#!/usr/bin/perl +-I/opt/sauron|#!/usr/bin/perl -I/usr/local/sauron|'


FROM debian:trixie-slim AS runtime

ENV DEBIAN_FRONTEND=noninteractive \
	LANG=C.UTF-8 \
	LC_ALL=C.UTF-8 \
	PERL5LIB=/usr/local/sauron

RUN apt-get update -qq \
	&& apt-get install -y --no-install-recommends \
		apache2 \
		curl \
		postgresql-client \
		perl \
		libcgi-pm-perl \
		libdbi-perl \
		libdbd-pg-perl \
		libnet-dns-perl \
		libnet-ip-perl \
		libnet-netmask-perl \
		libnetaddr-ip-perl \
		libtext-table-perl \
		libcryptx-perl \
		libjson-perl \
		libparse-recdescent-perl \
		libhtml-parser-perl \
		libdigest-hmac-perl \
		libencode-locale-perl \
	&& a2enmod cgid alias \
	&& a2disconf other-vhosts-access-log \
	# Stock Debian maps /cgi-bin/ → /usr/lib/cgi-bin; Sauron replaces that.
	&& a2disconf serve-cgi-bin \
	&& rm -rf /var/lib/apt/lists/*

# Installed Sauron tree + default config templates from builder
COPY --from=builder /usr/local/sauron /usr/local/sauron
COPY --from=builder /usr/local/etc/sauron /usr/local/etc/sauron

# Global CGI/icons conf (works with default site left enabled)
COPY docker/apache/sauron.conf /etc/apache2/conf-available/sauron.conf
COPY docker/entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN a2enconf sauron \
	&& chmod 755 /usr/local/bin/docker-entrypoint.sh \
	&& chown -R www-data:www-data /usr/local/sauron/logs /usr/local/sauron/tmp \
	&& chmod -R a+rX /usr/local/sauron /usr/local/etc/sauron

WORKDIR /usr/local/sauron

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=3 \
	CMD curl -sf -o /dev/null http://127.0.0.1/cgi-bin/sauron.cgi || exit 1

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["apache2"]
