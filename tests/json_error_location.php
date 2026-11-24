<?php
// php 8.6 adds where a decode failed to json_last_error_msg() and
// JsonException: "Syntax error near location LINE:COLUMN"
$cases = [
    '', '{', '[1,]', '{"a":1,}', "{\n  \"a\": 1,\n  \"b\": x\n}", "\r\n\r\n  [tru]",
    '"abc', "\"a\x00b\"", "\"a\x01\"", '"\u12"', '"\ud800"', "[\"\xff\"]",
    '[1] [2]', '{"\u0000a": 1}', '{"a" 1}', '[[[[1]]]]', "\"é\" x", "  é",
    '1.', '-', '01', "\t\t\t{\"x\":[1,2,", '{"a":{"b":', 'nul', '[1,2,3,4,5,6,7,8,9, @]',
    "[\n1,\n2,\n\n\n3 4]",
];
foreach ($cases as $json) {
    $r = json_decode($json, false, 4);
    echo json_encode($json), ' => ', json_last_error(), ' ', json_last_error_msg(), "\n";
    try {
        json_decode($json, true, 4, JSON_THROW_ON_ERROR);
    } catch (JsonException $e) {
        echo '  ', $e->getCode(), ' ', $e->getMessage(), "\n";
    }
    var_dump(json_validate($json, 4));
    echo '  ', json_last_error_msg(), "\n";
}
// an object as array key that can't be a property name
var_dump(json_decode('{"\u0000x":1}'));
echo json_last_error_msg(), "\n";
// encode errors have no location
json_encode(NAN);
echo json_last_error_msg(), "\n";
json_encode("\xff");
echo json_last_error_msg(), "\n";
json_decode('[1]');
echo json_last_error_msg(), "\n";
