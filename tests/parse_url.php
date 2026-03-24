<?php

// full URL with all components
$url = parse_url("https://user:pass@example.com:8080/path/to/page?key=val&foo=bar#section");
echo $url["scheme"] . "\n";
echo $url["host"] . "\n";
echo $url["port"] . "\n";
echo $url["user"] . "\n";
echo $url["pass"] . "\n";
echo $url["path"] . "\n";
echo $url["query"] . "\n";
echo $url["fragment"] . "\n";

// simple URL, no port/user/pass/query/fragment
$url2 = parse_url("https://example.com/path");
echo $url2["scheme"] . "\n";
echo $url2["host"] . "\n";
echo $url2["path"] . "\n";
var_dump(isset($url2["port"]));
var_dump(isset($url2["user"]));
var_dump(isset($url2["query"]));
var_dump(isset($url2["fragment"]));

// no path
$url3 = parse_url("https://example.com");
echo $url3["scheme"] . "\n";
echo $url3["host"] . "\n";
var_dump(isset($url3["path"]));

// no query
$url4 = parse_url("https://example.com/path#frag");
echo $url4["path"] . "\n";
echo $url4["fragment"] . "\n";
var_dump(isset($url4["query"]));

// no fragment
$url5 = parse_url("https://example.com/path?q=1");
echo $url5["path"] . "\n";
echo $url5["query"] . "\n";
var_dump(isset($url5["fragment"]));

// path-only URL
$url6 = parse_url("/path/to/file");
echo $url6["path"] . "\n";
var_dump(isset($url6["scheme"]));
var_dump(isset($url6["host"]));

// path with query
$url7 = parse_url("/path?key=val");
echo $url7["path"] . "\n";
echo $url7["query"] . "\n";

// path with fragment
$url8 = parse_url("/path#section");
echo $url8["path"] . "\n";
echo $url8["fragment"] . "\n";

// query-only
$url9 = parse_url("?key=val&other=2");
echo $url9["query"] . "\n";
var_dump(isset($url9["scheme"]));

// fragment-only
$url10 = parse_url("#section");
echo $url10["fragment"] . "\n";
var_dump(isset($url10["scheme"]));

// protocol-relative
$url11 = parse_url("//example.com/path");
echo $url11["host"] . "\n";
echo $url11["path"] . "\n";
var_dump(isset($url11["scheme"]));

// protocol-relative with port
$url12 = parse_url("//example.com:9090/path");
echo $url12["host"] . "\n";
echo $url12["port"] . "\n";
echo $url12["path"] . "\n";

// file:// URL
$url13 = parse_url("file:///tmp/test.txt");
echo $url13["scheme"] . "\n";
echo $url13["path"] . "\n";

// ftp URL with user
$url14 = parse_url("ftp://admin@ftp.example.com/pub/file.txt");
echo $url14["scheme"] . "\n";
echo $url14["user"] . "\n";
echo $url14["host"] . "\n";
echo $url14["path"] . "\n";
var_dump(isset($url14["pass"]));

// standard port
$url15 = parse_url("https://example.com:443");
echo $url15["port"] . "\n";

// non-standard port
$url16 = parse_url("http://example.com:3000/api");
echo $url16["port"] . "\n";
echo $url16["path"] . "\n";

// no port
$url17 = parse_url("http://example.com/api");
var_dump(isset($url17["port"]));

// component extraction: PHP_URL_SCHEME
echo parse_url("https://example.com/path?q=1#frag", PHP_URL_SCHEME) . "\n";

// component extraction: PHP_URL_HOST
echo parse_url("https://example.com/path?q=1#frag", PHP_URL_HOST) . "\n";

// component extraction: PHP_URL_PORT
echo parse_url("https://example.com:8080/path", PHP_URL_PORT) . "\n";

// component extraction: PHP_URL_PORT when absent
var_dump(parse_url("https://example.com/path", PHP_URL_PORT));

// component extraction: PHP_URL_USER
echo parse_url("https://user:pass@example.com/path", PHP_URL_USER) . "\n";

// component extraction: PHP_URL_USER when absent
var_dump(parse_url("https://example.com/path", PHP_URL_USER));

// component extraction: PHP_URL_PASS
echo parse_url("https://user:pass@example.com/path", PHP_URL_PASS) . "\n";

// component extraction: PHP_URL_PASS when absent
var_dump(parse_url("https://example.com/path", PHP_URL_PASS));

// component extraction: PHP_URL_PATH
echo parse_url("https://example.com/path/to/file", PHP_URL_PATH) . "\n";

// component extraction: PHP_URL_PATH when absent
var_dump(parse_url("https://example.com", PHP_URL_PATH));

// component extraction: PHP_URL_QUERY
echo parse_url("https://example.com/path?key=val", PHP_URL_QUERY) . "\n";

// component extraction: PHP_URL_QUERY when absent
var_dump(parse_url("https://example.com/path", PHP_URL_QUERY));

// component extraction: PHP_URL_FRAGMENT
echo parse_url("https://example.com/path#frag", PHP_URL_FRAGMENT) . "\n";

// component extraction: PHP_URL_FRAGMENT when absent
var_dump(parse_url("https://example.com/path", PHP_URL_FRAGMENT));

// URL with encoded characters
$url18 = parse_url("https://example.com/path%20with%20spaces?q=hello%20world");
echo $url18["path"] . "\n";
echo $url18["query"] . "\n";

// URL with special chars in query
$url19 = parse_url("https://example.com/search?q=a%26b&lang=en");
echo $url19["query"] . "\n";

// empty string
$url20 = parse_url("");
echo $url20["path"] . "\n";
var_dump(isset($url20["scheme"]));
var_dump(isset($url20["host"]));

// user without password
$url21 = parse_url("https://user@example.com/path");
echo $url21["user"] . "\n";
var_dump(isset($url21["pass"]));

// host only with scheme
$url22 = parse_url("http://localhost");
echo $url22["scheme"] . "\n";
echo $url22["host"] . "\n";

// complex query string
$url23 = parse_url("https://example.com/api?a=1&b=2&c=3");
echo $url23["query"] . "\n";

// mailto-style (scheme:path, no //)
$url24 = parse_url("mailto:user@example.com");
echo $url24["scheme"] . "\n";
echo $url24["path"] . "\n";
var_dump(isset($url24["host"]));

// path with dots
$url25 = parse_url("https://example.com/path/../other/./file");
echo $url25["path"] . "\n";

// empty query
$url26 = parse_url("https://example.com/path?");
var_dump(isset($url26["query"]));
echo $url26["query"] . "\n";

// empty fragment
$url27 = parse_url("https://example.com/path#");
var_dump(isset($url27["fragment"]));
echo $url27["fragment"] . "\n";

// port extraction from full URL
echo parse_url("https://user:pass@example.com:8080/path?q=1#frag", PHP_URL_PORT) . "\n";

// path-only with component extraction
echo parse_url("/path/to/file", PHP_URL_PATH) . "\n";
var_dump(parse_url("/path/to/file", PHP_URL_HOST));
