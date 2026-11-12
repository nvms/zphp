<?php
// parse_url follows php_url_parse_ex2: a host:port without a scheme, schemes
// without a slash after them, ports of up to five digits, control characters
// replaced in every component
$urls = [
    "64.246.30.37:80/",
    "www.php.net:80",
    "www.php.net:80/index.php?a=1#frag",
    "zlib:http://foo@bar",
    "mailto:someone@example.com",
    "http://user:pass@host:8080/p?q#f",
    "//example.com/path",
    "/just/a/path?x",
    "file:///c:/dir/file.txt",
    "file:///etc/passwd",
    "http://[::1]:80/x",
    "http://host:+80/",
    "http://host:0/",
    "http://host:123456/",
    "http://host:abc/",
    "http://:80",
    ":",
    "a:65536",
    "a:65535",
    "http://a\x01b/c\x7fd",
    "?",
    "#",
    "",
    "scheme:",
    "x://::abc/?",
];
foreach ($urls as $u) {
    echo json_encode($u), "\n";
    var_dump(parse_url($u));
}
foreach (range(-1, 7) as $c) {
    var_dump(parse_url("http://u:p@h:9/p?q#f", $c));
}
try {
    parse_url("http://h/", 8);
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
