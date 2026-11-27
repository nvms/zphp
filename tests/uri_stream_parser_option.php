<?php
// the http and ftp wrappers parse their url with the parser the context's
// uri_parser_class option names; urls only one parser rejects fail before
// any connection
foreach (["not-exists", 42, "uri\\rfc3986\\uri", ["Uri\\WhatWg\\Url"]] as $bad) {
    foreach (["http" => "http://example.com", "ftp" => "ftp://example.com/x"] as $wrapper => $url) {
        $context = stream_context_create([$wrapper => ["uri_parser_class" => $bad]]);
        try {
            var_dump(file_get_contents($url, context: $context));
        } catch (Throwable $e) {
            echo get_class($e), ': ', $e->getMessage(), "\n";
        }
    }
}

$cases = [
    [null, "http:///example.com"],
    ["parse_url", "http:///example.com"],
    [Uri\Rfc3986\Uri::class, "http://éxamplé.com"],
    [Uri\Rfc3986\Uri::class, "http://exa mple.com/"],
    [Uri\WhatWg\Url::class, "http://exa%23mple.org"],
    [Uri\WhatWg\Url::class, "http://[::1/"],
    [Uri\Rfc3986\Uri::class, "ftp://é/x"],
    [Uri\WhatWg\Url::class, "ftp://a b/x"],
];
foreach ($cases as [$parser, $url]) {
    $wrapper = substr($url, 0, strpos($url, ":"));
    $context = stream_context_create([$wrapper => ["uri_parser_class" => $parser]]);
    echo var_export($parser, true), " $url\n";
    var_dump(@file_get_contents($url, context: $context));
    echo error_get_last()['message'] ?? '', "\n";
}
try {
    rename("ftp://example.com/a", "ftp://example.com/b", stream_context_create(["ftp" => ["uri_parser_class" => "nope"]]));
} catch (ValueError $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}
