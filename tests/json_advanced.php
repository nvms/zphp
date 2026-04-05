<?php

// json_decode returns stdClass by default
$obj = json_decode('{"name":"test","age":30}');
echo get_class($obj) . "\n";
echo $obj->name . "\n";
echo $obj->age . "\n";

// nested objects
$nested = json_decode('{"user":{"name":"alice","address":{"city":"NYC"}}}');
echo get_class($nested->user) . "\n";
echo $nested->user->address->city . "\n";

// json_decode with assoc=true returns array
$arr = json_decode('{"name":"test"}', true);
echo $arr['name'] . "\n";

// empty object
$empty = json_decode('{}');
echo get_class($empty) . "\n";

// JSON_FORCE_OBJECT
echo json_encode([1, 2, 3], JSON_FORCE_OBJECT) . "\n";
echo json_encode([], JSON_FORCE_OBJECT) . "\n";

// JSON_NUMERIC_CHECK
echo json_encode(["val" => "42"], JSON_NUMERIC_CHECK) . "\n";
echo json_encode(["val" => "3.14"], JSON_NUMERIC_CHECK) . "\n";
echo json_encode(["val" => "hello"], JSON_NUMERIC_CHECK) . "\n";

// depth limit
$result = json_decode('{"a":{"b":{"c":1}}}', true, 2);
echo var_export($result, true) . "\n";
echo json_last_error() . "\n";

// json_decode preserves types
$data = json_decode('{"int":42,"float":3.14,"bool":true,"null":null,"str":"hello"}');
echo gettype($data->int) . "\n";
echo gettype($data->float) . "\n";
echo gettype($data->bool) . "\n";
echo gettype($data->null) . "\n";
echo gettype($data->str) . "\n";
