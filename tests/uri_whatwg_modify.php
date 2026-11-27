<?php
// Uri\WhatWg\Url: with*() setters, equals, serialization, UrlBuilder with
// and without a base, url_percent_encode, the exception and error classes
use Uri\WhatWg\Url;
use Uri\WhatWg\UrlBuilder;
use Uri\WhatWg\UrlPercentEncodingMode;
use Uri\WhatWg\UrlValidationError;
use Uri\WhatWg\UrlValidationErrorType;
use Uri\WhatWg\InvalidUrlException;

function errors(array $errors): string {
    return implode(", ", array_map(fn($e) => $e->type->name . ($e->failure ? "!" : "") . "@" . json_encode($e->context), $errors));
}

function attempt(string $label, callable $f): void {
    try {
        $r = $f();
        echo "$label: ", $r instanceof Url ? $r->toAsciiString() : var_export($r, true), "\n";
    } catch (InvalidUrlException $e) {
        echo "$label: ", get_class($e), ": ", $e->getMessage(), " [", errors($e->errors), "]\n";
    } catch (Throwable $e) {
        echo "$label: ", get_class($e), ": ", $e->getMessage(), "\n";
    }
}

$u = new Url("https://user:pass@example.com:8443/a/b?q=1#frag");
attempt('scheme', fn() => $u->withScheme("http"));
attempt('scheme to non-special', fn() => $u->withScheme("foo"));
attempt('scheme bad', fn() => $u->withScheme("1"));
attempt('username', fn() => $u->withUsername("new user"));
attempt('username null', fn() => $u->withUsername(null));
attempt('password', fn() => $u->withPassword("p@ss"));
attempt('host', fn() => $u->withHost("bücher.de"));
attempt('host ipv4', fn() => $u->withHost("0x7f.0.0.1"));
attempt('host bad', fn() => $u->withHost("exa mple"));
attempt('host empty', fn() => $u->withHost(""));
attempt('port', fn() => $u->withPort(443));
attempt('port null', fn() => $u->withPort(null));
attempt('port big', fn() => $u->withPort(70000));
attempt('path', fn() => $u->withPath("/x/../y z"));
attempt('path relative', fn() => $u->withPath("rel"));
attempt('query', fn() => $u->withQuery("?a=b c"));
attempt('query null', fn() => $u->withQuery(null));
attempt('fragment', fn() => $u->withFragment("#top"));
attempt('fragment null', fn() => $u->withFragment(null));
$opaque = new Url("mailto:someone@example.com");
attempt('opaque host', fn() => $opaque->withHost("example.com"));
attempt('opaque path', fn() => $opaque->withPath("other@example.com"));
attempt('original', fn() => $u);

$a = new Url("HTTPS://EXAMPLE.com:443/a?x#one");
$b = new Url("https://example.com/a?x#two");
var_dump($a->equals($b), $a->equals($b, Uri\UriComparisonMode::IncludeFragment));
$s = serialize($a);
echo $s, "\n";
var_dump(unserialize($s)->toAsciiString());
try {
    unserialize('O:14:"Uri\WhatWg\Url":2:{i:0;a:1:{s:3:"uri";s:3:"a:b";}i:1;a:1:{s:1:"x";i:1;}}');
} catch (Throwable $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
var_dump((clone $a)->toAsciiString());

$builder = new UrlBuilder();
var_dump($builder);
attempt('build', fn() => $builder->setScheme("https")->setUsername("me")->setPassword("secret")->setHost("EXAMPLE.com")->setPort(8080)->setPath("/a b")->setQuery("q")->setFragment("f")->build());
attempt('build soft', function () {
    $url = (new UrlBuilder())->setScheme("https")->setHost("example.com")->setFragment("a\tb")->build(softErrors: $soft);
    echo errors($soft), "\n";
    return $url;
});
attempt('build opaque', fn() => (new UrlBuilder())->setScheme("mailto")->setPath("x@example.com")->build());
attempt('build no host', fn() => (new UrlBuilder())->setScheme("https")->build());
attempt('build user no host', fn() => (new UrlBuilder())->setScheme("foo")->setUsername("u")->build());
$base = new Url("https://example.com/dir/page?x#y");
attempt('build reference', fn() => (new UrlBuilder())->setPath("../other")->setQuery("z")->build($base));
attempt('build reference host', fn() => (new UrlBuilder())->setHost("other.example")->setPath("/p")->build($base));
attempt('build reference port', fn() => (new UrlBuilder())->setPort(1)->build($base));
attempt('set bad scheme', fn() => (new UrlBuilder())->setScheme("1a"));
attempt('set bad host', fn() => (new UrlBuilder())->setHost("a/b"));
attempt('set bad ipv6', fn() => (new UrlBuilder())->setHost("[::1"));
attempt('set bad port', fn() => (new UrlBuilder())->setPort(-1));
attempt('set big port', fn() => (new UrlBuilder())->setPort(65536));
var_dump($builder->reset());

foreach (UrlPercentEncodingMode::cases() as $mode) {
    echo $mode->name, ": ", Uri\WhatWg\url_percent_encode("a b/c?d#e%f'g\"<>`{}|\\^ü\x01=&+", $mode), "\n";
}

$err = new UrlValidationError("ctx", UrlValidationErrorType::HostMissing, true);
var_dump($err);
$e = new InvalidUrlException("message", [$err], 5);
var_dump($e->errors === [$err], $e->getCode());
try {
    new InvalidUrlException("m", ["not an error"]);
} catch (ValueError $ve) {
    echo get_class($ve), ": ", $ve->getMessage(), "\n";
}
try {
    $e->__construct("again");
} catch (Error $re) {
    echo get_class($re), ": ", $re->getMessage(), "\n";
}
var_dump($e->getMessage());
var_dump(array_map(fn($c) => $c->name, UrlValidationErrorType::cases()));
var_dump(Uri\WhatWg\UrlHostType::cases(), Uri\Rfc3986\UriHostType::cases(), Uri\Rfc3986\UriType::cases());
var_dump(get_parent_class(InvalidUrlException::class), get_parent_class(Uri\InvalidUriException::class), get_parent_class(Uri\UriError::class));
