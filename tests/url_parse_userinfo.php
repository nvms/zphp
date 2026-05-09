<?php
print_r(parse_url("https://user:pass@example.com:8080/path/file?key=val&x=1#frag"));
print_r(parse_url("ftp://example.com"));
print_r(parse_url("/just/a/path?q=1"));
print_r(parse_url("//cdn.example.com/x"));
print_r(parse_url("https://example.com/?a=1&b=2"));
print_r(parse_url("https://example.com#frag"));
print_r(parse_url("https://[::1]:8080/path"));
echo parse_url("https://user:p@ss@example.com/x", PHP_URL_USER), "\n";
echo parse_url("https://user:p@ss@example.com/x", PHP_URL_PASS), "\n";
echo parse_url("https://user:p@ss@example.com/x", PHP_URL_HOST), "\n";
echo parse_url("file:///etc/passwd", PHP_URL_PATH), "\n";
echo parse_url("mailto:foo@bar.com", PHP_URL_PATH), "\n";
echo parse_url("not a url", PHP_URL_HOST) === null ? "null\n" : "non-null\n";
// urlencode
echo urlencode("hello world"), "\n";
echo urlencode("a+b/c?d=e&f"), "\n";
echo urlencode("café"), "\n";
echo urlencode("~!@#$%^&*()_+-="), "\n";
echo rawurlencode("hello world"), "\n";
echo rawurlencode("a+b/c?d=e&f"), "\n";
echo urldecode("hello+world%20again"), "\n";
echo rawurldecode("hello+world%20again"), "\n";
// http_build_query
echo http_build_query(["a" => 1, "b" => 2, "c" => "hello world"]), "\n";
echo http_build_query(["arr" => [1, 2, 3]]), "\n";
echo http_build_query(["arr" => ["x" => 1, "y" => 2]]), "\n";
echo http_build_query(["nested" => ["a" => ["b" => "c"]]]), "\n";
echo http_build_query(["k" => 1], "p_", "&", PHP_QUERY_RFC1738), "\n"; // numeric prefix
echo http_build_query([1, 2, 3], "p_"), "\n"; // numeric keys get prefix
echo http_build_query(["a" => "x y", "b" => "x+y"], "", "&", PHP_QUERY_RFC3986), "\n";
echo http_build_query(["a" => null, "b" => false, "c" => true, "d" => ""]), "\n";
// parse_str
parse_str("a=1&b=2&c[]=x&c[]=y", $r);
print_r($r);
parse_str("a[x]=1&a[y]=2", $r);
print_r($r);
parse_str("a=hello+world", $r);
print_r($r);
parse_str("foo bar=baz", $r); // space converted to underscore in key
print_r($r);
parse_str("foo.bar=baz", $r); // dot converted to underscore
print_r($r);
