# TLS and HTTP/2

zphp has built-in TLS support via OpenSSL and HTTP/2 via nghttp2. No reverse proxy needed.

## Enabling TLS

Provide a certificate and private key:

```
$ zphp serve app.php --tls-cert cert.pem --tls-key key.pem
listening on https://0.0.0.0:8080 (14 workers)
```

This enables HTTPS on the same port. Both the certificate and key flags are required together.

## HTTP/2

When TLS is enabled, HTTP/2 is automatically negotiated via ALPN. Clients that support HTTP/2 (all modern browsers) will use it. Clients that don't will fall back to HTTP/1.1.

HTTP/2 features supported:
- Stream multiplexing (multiple requests over a single connection)
- Header compression (HPACK)
- Server-side stream management

No configuration needed. If TLS is on, HTTP/2 is available.

## Self-signed certificates for development

For local development, generate a self-signed certificate:

```
$ openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem \
    -days 365 -nodes -subj '/CN=localhost'
```

Then serve with TLS:

```
$ zphp serve app.php --tls-cert cert.pem --tls-key key.pem --port 8443
```

```
$ curl -k https://localhost:8443/
```

## Production TLS

For production, use certificates from Let's Encrypt or your certificate authority. Point `--tls-cert` at the fullchain certificate and `--tls-key` at the private key.

You can also run zphp behind a reverse proxy (nginx, Caddy, etc.) that handles TLS termination, and serve plain HTTP from zphp. Both approaches work.
