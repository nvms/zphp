<?php
echo json_encode(["a"=>1]), "\n";
echo json_encode([]), "\n";
echo json_encode(new stdClass), "\n";

echo json_encode([], JSON_FORCE_OBJECT), "\n";
echo json_encode([1,2,3], JSON_FORCE_OBJECT), "\n";
echo json_encode(["a"=>1,"b"=>2], JSON_FORCE_OBJECT), "\n";

echo json_encode(["a"=>1,"b"=>["c"=>2,"d"=>[3,4]]], JSON_PRETTY_PRINT), "\n";
echo json_encode([1,2,3], JSON_PRETTY_PRINT), "\n";
echo json_encode([], JSON_PRETTY_PRINT), "\n";
echo json_encode(new stdClass, JSON_PRETTY_PRINT), "\n";
echo json_encode(["nested"=>["deep"=>["x"=>1]]], JSON_PRETTY_PRINT), "\n";

echo json_encode("a/b/c"), "\n";
echo json_encode("a/b/c", JSON_UNESCAPED_SLASHES), "\n";
echo json_encode(["url"=>"https://example.com/path"]), "\n";
echo json_encode(["url"=>"https://example.com/path"], JSON_UNESCAPED_SLASHES), "\n";

echo json_encode("héllo"), "\n";
echo json_encode("héllo", JSON_UNESCAPED_UNICODE), "\n";
echo json_encode("日本語"), "\n";
echo json_encode("日本語", JSON_UNESCAPED_UNICODE), "\n";
echo json_encode(["k"=>"日"], JSON_PRETTY_PRINT|JSON_UNESCAPED_UNICODE), "\n";

echo json_encode(["url"=>"https://example.com"], JSON_UNESCAPED_SLASHES|JSON_PRETTY_PRINT), "\n";

print_r(json_decode('{"a":1,"b":2}'));
print_r(json_decode('{"a":1,"b":2}', true));
print_r(json_decode('{"a":1,"b":2}', false));
print_r(json_decode('[1,2,3]'));
print_r(json_decode('[1,2,3]', true));
print_r(json_decode('null'));
echo var_export(json_decode('null'), true), "\n";
echo var_export(json_decode('true'), true), "\n";
echo var_export(json_decode('false'), true), "\n";
echo var_export(json_decode('42'), true), "\n";
echo var_export(json_decode('"str"'), true), "\n";

print_r(json_decode('{"x":{"y":{"z":1}}}', true));
$r = json_decode('{"x":{"y":{"z":1}}}', true, 4);
print_r($r);
$r = json_decode('{"x":{"y":{"z":1}}}', true, 2);
echo var_export($r, true), "\n";
$r = json_decode('[[[[1]]]]', true, 3);
echo var_export($r, true), "\n";

echo var_export(json_decode('not valid'), true), "\n";
echo json_last_error(), "\n";
echo json_decode('{"a":1}') ? "ok" : "no", "\n";
echo json_last_error(), "\n";

try {
    json_decode('not valid', true, 512, JSON_THROW_ON_ERROR);
    echo "no\n";
} catch (\JsonException $e) {
    echo "ex:", strlen($e->getMessage())>0?"y":"n", "\n";
}

try {
    json_encode("\xff\xfe", JSON_THROW_ON_ERROR);
    echo "no-err\n";
} catch (\JsonException $e) {
    echo "ex-enc\n";
}

echo var_export(json_decode('1234567890123456789'), true), "\n";
$r = json_decode('1234567890123456789', false, 512, JSON_BIGINT_AS_STRING);
echo var_export($r, true), "\n";

$r = json_decode('{"big":1234567890123456789}', true, 512, JSON_BIGINT_AS_STRING);
print_r($r);

$r = json_decode('{"a":1}', false, 512, JSON_OBJECT_AS_ARRAY);
print_r($r);
$r = json_decode('{"a":[1,2]}', false, 512, JSON_OBJECT_AS_ARRAY);
print_r($r);

echo json_encode([1.5, 2.5]), "\n";
echo json_encode(["a"=>1.0]), "\n";
echo json_encode([true, false, null]), "\n";
echo json_encode(["nested"=>[]]), "\n";
echo json_encode(["nested"=>[]], JSON_FORCE_OBJECT), "\n";
echo json_encode(["nested"=>[1]], JSON_FORCE_OBJECT), "\n";

echo json_encode("tab\there"), "\n";
echo json_encode("line\nbreak"), "\n";
echo json_encode("back\\slash"), "\n";
echo json_encode("quote\"here"), "\n";
echo json_encode(chr(1) . chr(2)), "\n";
