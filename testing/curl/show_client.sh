#!/bin/sh

curl --cacert /etc/ssl/certs/ca-certificates.crt \
     --data-binary "@show_client.xml" \
     "https://secure.sendanor.fi/~jheusala/ccd/ccd-server.cgi"
