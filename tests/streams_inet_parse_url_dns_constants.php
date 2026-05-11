<?php
echo function_exists("stream_wrapper_register") ? "y" : "n", "\n";
echo function_exists("stream_socket_client") ? "y" : "n", "\n";
echo function_exists("fsockopen") ? "y" : "n", "\n";
echo function_exists("gethostbyname") ? "y" : "n", "\n";
echo function_exists("dns_get_record") ? "y" : "n", "\n";
echo function_exists("inet_pton") ? "y" : "n", "\n";
echo function_exists("inet_ntop") ? "y" : "n", "\n";
echo function_exists("ip2long") ? "y" : "n", "\n";
echo function_exists("long2ip") ? "y" : "n", "\n";
echo function_exists("parse_url") ? "y" : "n", "\n";

$ip4 = inet_pton("127.0.0.1");
echo bin2hex($ip4), "\n";
echo strlen($ip4), "\n";
echo inet_ntop($ip4), "\n";

$ip6 = inet_pton("::1");
echo strlen($ip6), "\n";
echo inet_ntop($ip6), "\n";

var_dump(@inet_pton("not.an.ip"));

echo ip2long("127.0.0.1"), "\n";
echo ip2long("0.0.0.0"), "\n";
echo ip2long("255.255.255.255"), "\n";
echo long2ip(0), "\n";
echo long2ip(2130706433), "\n";

$u = parse_url("https://user:pass@example.com:8080/path/file.php?key=value&other=1#frag");
print_r($u);

echo parse_url("https://example.com", PHP_URL_HOST), "\n";
echo parse_url("https://example.com:80/p", PHP_URL_PORT), "\n";
echo parse_url("https://e.com/p?q=1", PHP_URL_QUERY), "\n";

$u = parse_url("relative/path?q=1");
print_r($u);

$u = parse_url("/absolute/path");
print_r($u);

$u = parse_url("file:///etc/passwd");
print_r($u);

echo defined("PHP_URL_SCHEME") ? "y" : "n", "\n";
echo defined("PHP_URL_HOST") ? "y" : "n", "\n";
echo defined("PHP_URL_PORT") ? "y" : "n", "\n";
echo defined("PHP_URL_USER") ? "y" : "n", "\n";
echo defined("PHP_URL_PASS") ? "y" : "n", "\n";
echo defined("PHP_URL_PATH") ? "y" : "n", "\n";
echo defined("PHP_URL_QUERY") ? "y" : "n", "\n";
echo defined("PHP_URL_FRAGMENT") ? "y" : "n", "\n";

class MyWrapper {
    public function stream_open($path, $mode, $opts, &$opath) { return true; }
    public function stream_read($count) { return ""; }
    public function stream_eof() { return true; }
    public function stream_close() {}
}

if (!in_array("mywrap", stream_get_wrappers())) {
    stream_wrapper_register("mywrap", "MyWrapper");
}
echo in_array("mywrap", stream_get_wrappers()) ? "y" : "n", "\n";

$wrappers = stream_get_wrappers();
echo in_array("http", $wrappers) ? "y" : "n", "\n";
echo in_array("file", $wrappers) ? "y" : "n", "\n";
echo in_array("php", $wrappers) ? "y" : "n", "\n";

echo bin2hex(inet_pton("192.168.1.1")), "\n";
echo inet_ntop(hex2bin("c0a80101")), "\n";

echo defined("DNS_A") ? "y" : "n", "\n";
echo defined("DNS_CNAME") ? "y" : "n", "\n";
echo defined("DNS_MX") ? "y" : "n", "\n";
echo defined("DNS_AAAA") ? "y" : "n", "\n";
echo defined("DNS_TXT") ? "y" : "n", "\n";
echo defined("DNS_NS") ? "y" : "n", "\n";

echo "1.2.3.4" === long2ip(ip2long("1.2.3.4")) ? "y" : "n", "\n";
echo ip2long("10.0.0.1") > 0 ? "y" : "n", "\n";
