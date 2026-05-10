<?php
print_r(parse_url("https://user:pass@host.example.com:8080/path/to/resource?q=v&x=y#frag"));
print_r(parse_url("https://example.com"));
print_r(parse_url("//example.com/path"));
print_r(parse_url("/just/a/path"));
print_r(parse_url("http://[::1]:8080/path"));
print_r(parse_url("ftp://user@host"));
print_r(parse_url("mailto:foo@bar.com"));
print_r(parse_url("file:///tmp/foo.txt"));

echo parse_url("https://example.com/path?q=1#frag", PHP_URL_SCHEME), "\n";
echo parse_url("https://example.com/path?q=1#frag", PHP_URL_HOST), "\n";
echo parse_url("https://example.com:443/path", PHP_URL_PORT), "\n";
echo parse_url("https://example.com/path?q=1#frag", PHP_URL_PATH), "\n";
echo parse_url("https://example.com/path?q=1#frag", PHP_URL_QUERY), "\n";
echo parse_url("https://example.com/path?q=1#frag", PHP_URL_FRAGMENT), "\n";
echo var_export(parse_url("https://example.com/path", PHP_URL_QUERY), true), "\n";
echo var_export(parse_url("https://user@example.com", PHP_URL_USER), true), "\n";
echo var_export(parse_url("https://user:pw@example.com", PHP_URL_PASS), true), "\n";

echo http_build_query(["a"=>1,"b"=>2]), "\n";
echo http_build_query(["a"=>1,"b"=>2], "", "&"), "\n";
echo http_build_query(["a"=>1,"b"=>2], "", "|"), "\n";
echo http_build_query(["a"=>"hello world","b"=>"x&y"]), "\n";
echo http_build_query(["a"=>["x","y","z"]]), "\n";
echo http_build_query(["a"=>["k"=>"v","n"=>"m"]]), "\n";
echo http_build_query(["filter"=>["status"=>["active","pending"],"type"=>"user"]]), "\n";
echo http_build_query([1,2,3]), "\n";
echo http_build_query([1,2,3], "p_"), "\n";
echo http_build_query(["a"=>1,2,3], "p_"), "\n";
echo http_build_query([]), "\n";
echo http_build_query(["a"=>true,"b"=>false,"c"=>null]), "\n";
echo http_build_query(["x"=>1.5,"y"=>"str"]), "\n";

echo urlencode("hello world"), "\n";
echo urlencode("a+b=c&d"), "\n";
echo urlencode("foo bar/baz"), "\n";
echo urlencode("(){}[]"), "\n";
echo urlencode("~a~b~"), "\n";
echo urlencode(""), "\n";

echo rawurlencode("hello world"), "\n";
echo rawurlencode("a+b=c&d"), "\n";
echo rawurlencode("foo bar/baz"), "\n";
echo rawurlencode("~a~b~"), "\n";

echo urldecode("hello%20world"), "\n";
echo urldecode("hello+world"), "\n";
echo urldecode("a%2Bb%3Dc"), "\n";
echo rawurldecode("hello%20world"), "\n";
echo rawurldecode("hello+world"), "\n";

echo base64_encode("hello"), "\n";
echo base64_encode("hi"), "\n";
echo base64_encode("h"), "\n";
echo base64_encode(""), "\n";
echo base64_encode("\x00\x01\x02\x03\x04"), "\n";
echo base64_decode("aGVsbG8="), "\n";
echo base64_decode("aGk="), "\n";
echo base64_decode("aA=="), "\n";
echo base64_decode(""), "\n";
echo base64_decode("aGVsbG8") === "hello" ? "lax-ok" : "lax-no", "\n";
echo var_export(base64_decode("!!!", true), true), "\n";
echo base64_decode("aGVsbG8=", true), "\n";

echo quoted_printable_encode("hello"), "\n";
echo quoted_printable_encode("héllo"), "\n";
echo quoted_printable_encode("hello world\n"), "\n";
echo quoted_printable_encode("=test="), "\n";
echo quoted_printable_decode("hello"), "\n";
echo quoted_printable_decode("h=C3=A9llo"), "\n";
echo quoted_printable_decode("=3Dtest=3D"), "\n";
echo quoted_printable_decode("a=\nb"), "\n";
echo quoted_printable_decode("a=\r\nb"), "\n";
