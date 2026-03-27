<?php

// default: slashes escaped
echo json_encode("path/to/file") . "\n";

// JSON_UNESCAPED_SLASHES
echo json_encode("path/to/file", JSON_UNESCAPED_SLASHES) . "\n";

// default: unicode escaped
echo json_encode("caf\xC3\xA9") . "\n";

// JSON_UNESCAPED_UNICODE
echo json_encode("caf\xC3\xA9", JSON_UNESCAPED_UNICODE) . "\n";

// combined flags
echo json_encode("caf\xC3\xA9/latte", JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) . "\n";

// json_last_error after valid decode
json_decode('{"a":1}');
echo json_last_error() . "\n";
echo json_last_error_msg() . "\n";

// json_last_error after invalid decode
json_decode("not json");
echo json_last_error() . "\n";
echo json_last_error_msg() . "\n";

// json_last_error resets after successful call
json_decode('{"b":2}');
echo json_last_error() . "\n";
echo json_last_error_msg() . "\n";

// JSON_THROW_ON_ERROR with json_decode
try {
    json_decode("{bad}", false, 512, JSON_THROW_ON_ERROR);
    echo "no exception\n";
} catch (JsonException $e) {
    echo "decode: " . $e->getMessage() . "\n";
}

// JSON_THROW_ON_ERROR with json_encode (NAN)
try {
    json_encode(NAN, JSON_THROW_ON_ERROR);
    echo "nan encoded\n";
} catch (JsonException $e) {
    echo "encode: " . $e->getMessage() . "\n";
}

// arrays and objects with flags
$data = ["url" => "http://example.com/api", "name" => "caf\xC3\xA9"];
echo json_encode($data) . "\n";
echo json_encode($data, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) . "\n";

// nested slashes
echo json_encode(["a/b", "c/d"]) . "\n";
echo json_encode(["a/b", "c/d"], JSON_UNESCAPED_SLASHES) . "\n";
