# Static Files

`zphp serve` serves static files automatically from the same directory as your PHP file. No configuration required.

## How it works

When a request comes in, zphp checks if the path maps to a file on disk in the document root (the directory containing your PHP entry point). If the file exists and isn't a `.php` file, it's served directly. If it doesn't exist or is a `.php` request, your PHP entry point handles the request.

```
project/
  app.php         <- entry point
  style.css       <- served as static file
  script.js       <- served as static file
  images/
    logo.png      <- served as static file
```

```
$ zphp serve project/app.php
```

- `GET /style.css` serves `project/style.css`
- `GET /images/logo.png` serves `project/images/logo.png`
- `GET /anything-else` executes `project/app.php`

## Supported content types

zphp sets the correct `Content-Type` header based on file extension:

| Extensions | Content-Type |
|---|---|
| `.html`, `.htm` | text/html |
| `.css` | text/css |
| `.js`, `.mjs` | application/javascript |
| `.json` | application/json |
| `.png` | image/png |
| `.jpg`, `.jpeg` | image/jpeg |
| `.gif` | image/gif |
| `.svg` | image/svg+xml |
| `.ico` | image/x-icon |
| `.webp` | image/webp |
| `.woff`, `.woff2` | font/woff, font/woff2 |
| `.pdf` | application/pdf |
| `.wasm` | application/wasm |

## Caching

Static files are served with:
- **ETag** headers based on file content
- **Cache-Control: max-age=3600** (1 hour)
- Automatic **304 Not Modified** responses when the client sends a matching `If-None-Match` header

## Compression

Text-based static files (HTML, CSS, JS, JSON, SVG) are gzip-compressed automatically when the client supports it.
