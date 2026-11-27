<?php
// Uri\Rfc3986\Uri: with*() builders and their refusals, resolution, equals,
// serialization, cloning and Uri\Rfc3986\UriBuilder
use Uri\Rfc3986\Uri;
use Uri\Rfc3986\UriBuilder;
use Uri\UriComparisonMode;

function attempt(string $label, callable $f): void {
    try {
        $r = $f();
        echo "$label: ", $r instanceof Uri ? $r->toRawString() : var_export($r, true), "\n";
    } catch (Throwable $e) {
        echo "$label: ", get_class($e), ": ", $e->getMessage(), "\n";
    }
}

$u = new Uri("https://user@example.com:8080/a/b?q#f");
attempt('scheme', fn() => $u->withScheme("HTTP"));
attempt('scheme bad', fn() => $u->withScheme("1x"));
attempt('scheme null', fn() => $u->withScheme(null));
attempt('userinfo', fn() => $u->withUserInfo("a:b"));
attempt('userinfo null', fn() => $u->withUserInfo(null));
attempt('userinfo bad', fn() => $u->withUserInfo("a@b"));
attempt('host', fn() => $u->withHost("[::1]"));
attempt('host ip4', fn() => $u->withHost("10.0.0.1"));
attempt('host null', fn() => $u->withHost(null));
attempt('host bad', fn() => $u->withHost("a b"));
attempt('port', fn() => $u->withPort(1));
attempt('port neg', fn() => $u->withPort(-1));
attempt('port null', fn() => $u->withPort(null));
attempt('path', fn() => $u->withPath("/x/../y"));
attempt('path empty', fn() => $u->withPath(""));
attempt('path relative', fn() => $u->withPath("rel"));
attempt('query', fn() => $u->withQuery("a=1&b=2"));
attempt('query null', fn() => $u->withQuery(null));
attempt('query bad', fn() => $u->withQuery("a#b"));
attempt('fragment', fn() => $u->withFragment("top"));
attempt('fragment bad', fn() => $u->withFragment("a#b"));
$noHost = new Uri("/only/path");
attempt('userinfo no host', fn() => $noHost->withUserInfo("x"));
attempt('port no host', fn() => $noHost->withPort(80));
attempt('original', fn() => $u);

$base = new Uri("http://a/b/c/d;p?q");
foreach (["g:h", "g", "./g", "g/", "/g", "//g", "?y", "g?y", "#s", "g#s", "g?y#s", ";x", "g;x", "", ".", "./", "..", "../", "../g", "../..", "../../", "../../g", "../../../g", "/./g", "/../g", "g.", ".g", "g..", "..g", "./../g", "./g/.", "g/./h", "g/../h", "g;x=1/./y", "g;x=1/../y"] as $ref) {
    echo "resolve '$ref': ", $base->resolve($ref)->toString(), "\n";
}
attempt('resolve bad', fn() => $base->resolve("a b"));

$a = new Uri("HTTP://EXAMPLE.com/%7e/x#one");
$b = new Uri("http://example.com/~/x#two");
var_dump($a->equals($b), $a->equals($b, UriComparisonMode::IncludeFragment), $a->equals($a, UriComparisonMode::IncludeFragment));

$s = serialize($a);
echo $s, "\n";
$back = unserialize($s);
var_dump($back->toRawString(), $back == $a);
var_dump($a->__serialize());
try {
    unserialize('O:15:"Uri\Rfc3986\Uri":2:{i:0;a:1:{s:3:"uri";s:5:"a b c";}i:1;a:0:{}}');
} catch (Throwable $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
try {
    $a->__unserialize([["uri" => "x"], []]);
} catch (Throwable $e) {
    echo get_class($e), ": ", $e->getMessage(), " / ", get_class($e->getPrevious()), ": ", $e->getPrevious()->getMessage(), "\n";
}
$c = clone $a;
var_dump($c->toString());

$builder = new UriBuilder();
var_dump($builder);
$built = $builder->setScheme("https")->setUserInfo("me")->setHost("example.com")->setPort(443)->setPath("/x")->setQuery("q=1")->setFragment("f")->build();
var_dump($built->toRawString());
attempt('build relative', fn() => (new UriBuilder())->setPath("a/b")->build(new Uri("https://example.com/dir/file")));
attempt('build colon path', fn() => (new UriBuilder())->setPath("a:b")->build());
attempt('build double slash', fn() => (new UriBuilder())->setPath("//x")->build());
attempt('build userinfo without host', fn() => (new UriBuilder())->setUserInfo("u")->build());
attempt('set bad scheme', fn() => (new UriBuilder())->setScheme("-"));
attempt('set bad host', fn() => (new UriBuilder())->setHost("[::1"));
attempt('set bad port', fn() => (new UriBuilder())->setPort(-5));
var_dump($builder->reset());
