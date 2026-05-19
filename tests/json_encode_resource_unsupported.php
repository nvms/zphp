<?php
// regression: json_encode() of a resource (fopen handle, etc.) returns false,
// sets json_last_error()=8 with msg 'Type is not supported', throws
// JsonException under JSON_THROW_ON_ERROR, and emits 'null' under
// JSON_PARTIAL_OUTPUT_ON_ERROR. zphp represents resources as objects with
// internal slot fields; without this special-case the slots would leak into
// the JSON output instead
$f = fopen('php://memory', 'r');

var_dump(json_encode($f) === false);
var_dump(json_last_error());
echo json_last_error_msg() . "\n";

try { json_encode($f, JSON_THROW_ON_ERROR); }
catch (\JsonException $e) { echo $e->getMessage() . "\n"; }

echo json_encode($f, JSON_PARTIAL_OUTPUT_ON_ERROR) . "\n";
echo json_encode(['ok' => 1, 'bad' => $f, 'after' => 2], JSON_PARTIAL_OUTPUT_ON_ERROR) . "\n";

// mb_list_encodings has the full PHP 8.4 set (79 entries) so feature detection
// in libraries that grep for specific encoding names finds them
$encs = mb_list_encodings();
echo count($encs) >= 79 ? "encs-ok\n" : "encs-bad: " . count($encs) . "\n";
foreach (['UTF-8', 'UTF-16', 'BASE64', 'HTML-ENTITIES', 'EUC-JP', 'BIG-5', 'KOI8-R'] as $e) {
    echo "$e: " . (in_array($e, $encs) ? 'y' : 'n') . "\n";
}
