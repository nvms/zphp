<?php
// Uri\Rfc3986\Uri: parsing, raw and normalized components, recomposition,
// type getters and the errors of a malformed uri
use Uri\Rfc3986\Uri;

function show(string $s): void {
    $u = Uri::parse($s);
    if ($u === null) {
        echo "$s: invalid\n";
        return;
    }
    echo "$s\n";
    echo "  raw: ", $u->toRawString(), "\n";
    echo "  normalized: ", $u->toString(), "\n";
    foreach (['Scheme', 'UserInfo', 'Username', 'Password', 'Host', 'Path', 'Query', 'Fragment'] as $c) {
        $raw = $u->{"getRaw$c"}();
        $norm = $u->{"get$c"}();
        echo "  $c: ", var_export($raw, true), $raw === $norm ? "" : " -> " . var_export($norm, true), "\n";
    }
    echo "  Port: ", var_export($u->getPort(), true), "\n";
    echo "  type: ", $u->getUriType()->name, ", host type: ", $u->getHostType()?->name ?? 'none', "\n";
}

foreach ([
    "https://user:pass@EXAMPLE.com:8080/a/../b/./c?q=1#f",
    "HTTP://%7Euser@Example.COM/%7e%41%2f",
    "http://[2001:DB8::1]:80/",
    "http://[v7.Fe]/",
    "http://1.2.3.4/x",
    "http://1.2.3.4.5/x",
    "//example.com/path",
    "/absolute/path",
    "relative/path?x",
    "",
    "mailto:someone@example.com",
    "urn:isbn:0451450523",
    "http://host:0080",
    "http://host:/p",
    "http://u@h",
    "http://:@h",
    "foo:/.//bar",
    "http://example.com/a b",
    "http://éxample.com",
    "http://host:99999999999999999999999",
    "1http://x",
] as $s) {
    show($s);
}

try {
    new Uri("http://exa mple.com");
} catch (\Uri\InvalidUriException $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
try {
    new Uri("http://h:99999999999999999999999");
} catch (\Uri\UriException $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
try {
    new Uri("a", new Uri("relative"));
} catch (\Uri\UriException $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
$u = new Uri("https://example.com");
try {
    $u->__construct("https://other.example");
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
var_dump($u);
var_dump(Uri::parse("http://x/%zz"));
