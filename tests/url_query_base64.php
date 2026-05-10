<?php
print_r(parse_url("https://user:pass@host.com:8080/path?q=1#frag"));
print_r(parse_url("http://example.com"));
print_r(parse_url("/just/path?a=b"));
print_r(parse_url("//host/path"));
print_r(parse_url("mailto:a@b.com"));
print_r(parse_url("file:///etc/passwd"));
print_r(parse_url("https://[::1]:443/v6"));
print_r(parse_url("ftp://ftp.example.com/pub/"));
var_dump(parse_url("http://:80")); // PHP false (no host)

echo parse_url("https://user:pass@host.com:8080/path?q=1#frag", PHP_URL_SCHEME), "\n";
echo parse_url("https://user:pass@host.com:8080/path?q=1#frag", PHP_URL_HOST), "\n";
echo parse_url("https://user:pass@host.com:8080/path?q=1#frag", PHP_URL_PORT), "\n";
echo parse_url("https://user:pass@host.com:8080/path?q=1#frag", PHP_URL_USER), "\n";
echo parse_url("https://user:pass@host.com:8080/path?q=1#frag", PHP_URL_PASS), "\n";
echo parse_url("https://user:pass@host.com:8080/path?q=1#frag", PHP_URL_PATH), "\n";
echo parse_url("https://user:pass@host.com:8080/path?q=1#frag", PHP_URL_QUERY), "\n";
echo parse_url("https://user:pass@host.com:8080/path?q=1#frag", PHP_URL_FRAGMENT), "\n";
var_dump(parse_url("http://example.com", PHP_URL_PATH));

echo http_build_query(["a" => 1, "b" => 2]), "\n";
echo http_build_query(["a" => "hello world", "b" => "a&b"]), "\n";
echo http_build_query(["a" => ["x", "y", "z"]]), "\n";
echo http_build_query(["a" => ["x" => 1, "y" => 2]]), "\n";
echo http_build_query(["a" => ["b" => ["c" => "d"]]]), "\n";

echo http_build_query([1, 2, 3]), "\n";
echo http_build_query([1, 2, 3], "n_"), "\n";

echo http_build_query(["a" => 1, "b" => 2], "", ";"), "\n";

echo http_build_query(["a" => "hello world"], "", "&", PHP_QUERY_RFC1738), "\n";
echo http_build_query(["a" => "hello world"], "", "&", PHP_QUERY_RFC3986), "\n";
echo http_build_query(["a" => "a~b"], "", "&", PHP_QUERY_RFC1738), "\n";
echo http_build_query(["a" => "a~b"], "", "&", PHP_QUERY_RFC3986), "\n";

echo http_build_query(["k" => "/+ /"]), "\n";
echo http_build_query(["k" => "/+ /"], "", "&", PHP_QUERY_RFC3986), "\n";

echo http_build_query(["a" => null, "b" => true, "c" => false, "d" => 0]), "\n";
echo http_build_query(["a" => "", "b" => "x"]), "\n";

echo http_build_query(["a" => [1, 2, 3]], "", "&", PHP_QUERY_RFC1738), "\n";

echo urlencode("hello world"), "\n";
echo rawurlencode("hello world"), "\n";
echo urlencode("a~b"), "\n";
echo rawurlencode("a~b"), "\n";
echo urlencode("a/b"), "\n";
echo rawurlencode("a/b"), "\n";
echo urlencode("a*b"), "\n";
echo rawurlencode("a*b"), "\n";

echo urldecode("hello+world"), "\n";
echo urldecode("hello%20world"), "\n";
echo rawurldecode("hello+world"), "\n";
echo rawurldecode("hello%20world"), "\n";

echo base64_encode("hello world"), "\n";
echo base64_encode("\x00\x01\x02\xff"), "\n";
echo base64_decode("aGVsbG8gd29ybGQ="), "\n";

var_dump(base64_decode("hello world!", true));
var_dump(base64_decode("aGVsbG8gd29ybGQ=", true));
var_dump(base64_decode('invalid!!!char', true));

echo base64_decode("aGVsbG8="), "\n";

echo base64_decode("aGVsbG8"), "\n";

$r = base64_decode("aGVsbG");
echo strlen($r), "\n";

parse_str("a=1&b=2", $r);
print_r($r);
parse_str("a[]=1&a[]=2", $r);
print_r($r);
parse_str("a[x]=1&a[y]=2", $r);
print_r($r);
parse_str("a[x][]=1&a[x][]=2", $r);
print_r($r);
parse_str("a=hello+world&b=a%26b", $r);
print_r($r);

parse_str("a.b=1&c d=2", $r);
print_r($r);
