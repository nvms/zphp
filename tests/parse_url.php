<?php

// full URL
$url = parse_url("https://user:pass@example.com:8080/path/to/page?key=val&foo=bar#section");
echo $url["scheme"] . "\n";
echo $url["host"] . "\n";
echo $url["port"] . "\n";
echo $url["user"] . "\n";
echo $url["pass"] . "\n";
echo $url["path"] . "\n";
echo $url["query"] . "\n";
echo $url["fragment"] . "\n";

// simple URL
$url2 = parse_url("https://example.com/path");
echo $url2["scheme"] . "\n";
echo $url2["host"] . "\n";
echo $url2["path"] . "\n";
echo isset($url2["port"]) ? "has port" : "no port";
echo "\n";

// component extraction
echo parse_url("https://example.com/path?q=1", PHP_URL_SCHEME) . "\n";
echo parse_url("https://example.com/path?q=1", PHP_URL_HOST) . "\n";
echo parse_url("https://example.com/path?q=1", PHP_URL_PATH) . "\n";
echo parse_url("https://example.com/path?q=1", PHP_URL_QUERY) . "\n";
echo parse_url("https://example.com:443", PHP_URL_PORT) . "\n";

// path only
$url3 = parse_url("/just/a/path?q=1");
echo $url3["path"] . "\n";
echo $url3["query"] . "\n";

// protocol-relative
$url4 = parse_url("//example.com/path");
echo $url4["host"] . "\n";
echo $url4["path"] . "\n";
