<?php
// Uri\WhatWg\Url: parsing with soft errors, hosts of every kind (idna,
// ipv4 number forms, ipv6), getters, recomposition and failures
use Uri\WhatWg\Url;

function errors(array $errors): string {
    return implode(", ", array_map(fn($e) => $e->type->name . ($e->failure ? "!" : "") . "@" . json_encode($e->context), $errors));
}

function show(string $s, ?Url $base = null): void {
    $u = Url::parse($s, $base, $errors);
    echo json_encode($s), ($base ? " against " . $base->toAsciiString() : ""), "\n";
    if ($errors) echo "  errors: ", errors($errors), "\n";
    if ($u === null) {
        echo "  invalid\n";
        return;
    }
    echo "  ascii: ", $u->toAsciiString(), "\n";
    echo "  unicode: ", $u->toUnicodeString(), "\n";
    echo "  scheme ", $u->getScheme(), $u->isSpecialScheme() ? " (special)" : "", ", user ", var_export($u->getUsername(), true), ", pass ", var_export($u->getPassword(), true), "\n";
    echo "  host ", var_export($u->getAsciiHost(), true), " / ", var_export($u->getUnicodeHost(), true), " (", $u->getHostType()?->name ?? 'none', "), port ", var_export($u->getPort(), true), "\n";
    echo "  path ", var_export($u->getPath(), true), ", query ", var_export($u->getQuery(), true), ", fragment ", var_export($u->getFragment(), true), "\n";
}

foreach ([
    "https://user:pa ss@EXAMPLE.com:443/a/../b/./c?q= 1#f g",
    "  http://example.com\t/x\n",
    "https://www.bücher.de/",
    "https://xn--bcher-kva.de/",
    "https://faß.ExAmPlE/",
    "http://0x7f.1/",
    "http://0300.0250.0.1/",
    "http://4294967295/",
    "http://4294967296/",
    "http://1.2.3.4.5/",
    "http://[::1]/",
    "http://[2001:db8:0:0:1:0:0:1]/",
    "http://[::ffff:192.168.0.1]/",
    "http://[1:2:3:4:5:6:7:8:9]/",
    "http://[::1/",
    "file:///C:/dir/file",
    "file://host/share",
    "file:c:\\x\\y",
    "mailto:someone@example.com",
    "data:text/plain,hello world",
    "foo://opaque host/p",
    "non-spec:/.//p",
    "http:\\\\example.com\\path",
    "https://ex%41mple.com/",
    "https://exa%23mple.org/",
    "http://example.com:65536/",
    "http://example.com:8a/",
    "http://@example.com/",
    "http://:@example.com/",
    "relative/path",
    "",
    "https://☃.net/",
    "https://xn--zz/",
    "wss://example.com:443/",
    "ftp://example.com:21/",
] as $s) {
    show($s);
}
$base = new Url("https://example.com/dir/page?x#y");
foreach (["../a", "?q", "#h", "//other.example/p", "/root", "", "file:x"] as $s) {
    show($s, $base);
}

try {
    new Url("http://exa mple.com", null, $soft);
} catch (Uri\WhatWg\InvalidUrlException $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
    echo "  ", errors($e->errors), "\n";
    var_dump($soft);
}
$u = new Url(" https://example.com ", softErrors: $soft);
echo errors($soft), "\n";
var_dump($u);
var_dump($u->resolve("x y", $resolveErrors)->toAsciiString(), errors($resolveErrors));
