<?php
// executed against every packaged release binary: touches each linked
// native library once so a missing or mislinked dependency fails the release
$checks = [
    "pcre" => preg_match('/^v(\d+)/', "v42") === 1,
    "sqlite" => (new PDO("sqlite::memory:"))->query("select 42 as n")->fetchColumn() == 42,
    "zlib" => gzdecode(gzencode("zphp")) === "zphp",
    "openssl" => strlen(openssl_random_pseudo_bytes(8)) === 8,
    "curl" => is_string(curl_version()["version"]),
    "libxml" => (new DOMDocument())->loadXML("<a>b</a>") === true,
    "json" => json_decode('{"ok":true}', true)["ok"] === true,
    "gmp" => gmp_strval(gmp_add("1", "2")) === "3",
    "gd" => imagecreatetruecolor(2, 2) !== false,
    "sodium" => strlen(sodium_crypto_generichash("x")) === 32,
    "intl" => class_exists("NumberFormatter"),
    "bcmath" => bcadd("0.1", "0.2", 1) === "0.3",
    "mbstring" => mb_strlen("h\u{e9}") === 2,
    "datetime" => (new DateTime("2024-01-01 00:00:00 UTC"))->format("U") === "1704067200",
];
$failed = array_keys(array_filter($checks, fn($ok) => !$ok));
echo "smoke: " . count($checks) . " checks, " . count($failed) . " failed", $failed ? " (" . implode(", ", $failed) . ")" : "", "\n";
exit($failed ? 1 : 0);
