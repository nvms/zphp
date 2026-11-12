<?php
// json_decode and json_validate read json as php's scanner and parser do:
// which error a malformed document reports, and what valid ones decode to
$docs = [
    '', ' ', '1', '-', '-0', '01', '1.', '1.5e', '1e5', '-1E-2', '.5', '+1', '0x10',
    '9223372036854775807', '9223372036854775808', '-9223372036854775808', '-9223372036854775809', '12345678901234567890',
    'null', 'nul', 'nullx', 'true ', ' false', 'TRUE',
    '"abc', '"a\\x"', '"\\u12"', '"\\u00e9"', '"\\ud834\\udd1e"', '"\\ud834"', '"\\udd1e"', '"\\ud834\\u0041"',
    "\"a\x01b\"", "\"tab\tin\"", "1\x00", "\x00", "\"\xff\"", "\xff", "é", "[1,]", "[,1]", "[1 2]",
    '[1}', '[}', '{]', '{"a":1]', '{"a" 1}', '{1:2}', '{"a":}', '{"a":1,}', '[[[1]]]', '{"":1}', "{\"\\u0000a\":1}",
    '{"1":"x","01":"y","-1":"z","-0":"w"}', '[1] ', "\r\n[1]\t", '[1]x', '{"a":{"b":[true,false,null]}}',
    "\"a\xc3\x28b\"", "\"a\xe2\x82b\"", "\"a\xf0\x80\x80A\"", "\"a\xed\xa0\x80b\"",
];
foreach ($docs as $d) {
    $v = json_decode($d, true);
    echo json_encode($d, JSON_INVALID_UTF8_SUBSTITUTE), " => ", var_export($v, true), " ", json_last_error(), " ", json_last_error_msg(), "\n";
    var_dump(json_validate($d), json_last_error());
}
foreach (["\"a\xff\xfeb\"", "[\"\xc0\xaf\"]", "{\"k\xff\":1}"] as $d) {
    var_dump(json_decode($d, false, 512, JSON_INVALID_UTF8_IGNORE));
    var_dump(json_decode($d, true, 512, JSON_INVALID_UTF8_SUBSTITUTE));
    var_dump(json_validate($d, 512, JSON_INVALID_UTF8_IGNORE));
}
// depth
var_dump(json_decode('[[1]]', true, 2), json_last_error());
var_dump(json_decode('[[1]]', true, 3), json_last_error());
var_dump(json_decode('[[x', true, 1), json_last_error());
var_dump(json_decode('1', true, 1), json_last_error());
var_dump(json_validate('{"a":{"b":1}}', 2), json_last_error());
foreach ([0, -1] as $depth) {
    try { json_decode('1', true, $depth); } catch (ValueError $e) { echo $e->getMessage(), "\n"; }
}
try { json_validate('1', 0); } catch (ValueError $e) { echo $e->getMessage(), "\n"; }
try { json_validate('1', 512, JSON_BIGINT_AS_STRING); } catch (ValueError $e) { echo $e->getMessage(), "\n"; }
var_dump(json_decode('12345678901234567890', false, 512, JSON_BIGINT_AS_STRING));
var_dump(json_decode('{"a":12345678901234567890}', false, 512, JSON_BIGINT_AS_STRING));
// objects: property names, duplicate keys, object_as_array
var_dump(json_decode('{"a":1,"a":2,"":3,"0":4}'));
var_dump(json_decode('{"a":{}}', null, 512, JSON_OBJECT_AS_ARRAY));
var_dump(json_decode('{"a":{}}', false, 512, JSON_OBJECT_AS_ARRAY));
var_dump(json_decode('{"\u0000ab":1}'), json_last_error_msg());
// throw on error keeps the previous error code
json_decode('[');
try { json_decode('{', false, 512, JSON_THROW_ON_ERROR); } catch (JsonException $e) { echo get_class($e), " ", $e->getCode(), " ", $e->getMessage(), "\n"; }
var_dump(json_last_error());
json_decode('[1]', false, 512, JSON_THROW_ON_ERROR);
var_dump(json_last_error());
