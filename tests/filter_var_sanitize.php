<?php
// filter_var - FILTER_VALIDATE_INT
var_dump(filter_var("42", FILTER_VALIDATE_INT));
var_dump(filter_var("0", FILTER_VALIDATE_INT));
var_dump(filter_var("-5", FILTER_VALIDATE_INT));
var_dump(filter_var("abc", FILTER_VALIDATE_INT));
var_dump(filter_var("3.14", FILTER_VALIDATE_INT));
var_dump(filter_var("123abc", FILTER_VALIDATE_INT));
var_dump(filter_var(42, FILTER_VALIDATE_INT));
var_dump(filter_var("", FILTER_VALIDATE_INT));
var_dump(filter_var(null, FILTER_VALIDATE_INT));

// FILTER_VALIDATE_EMAIL
var_dump(filter_var("user@example.com", FILTER_VALIDATE_EMAIL));
var_dump(filter_var("not-an-email", FILTER_VALIDATE_EMAIL));
var_dump(filter_var("user@", FILTER_VALIDATE_EMAIL));
var_dump(filter_var("@example.com", FILTER_VALIDATE_EMAIL));
var_dump(filter_var("user@domain.co.uk", FILTER_VALIDATE_EMAIL));
var_dump(filter_var("user+tag@example.com", FILTER_VALIDATE_EMAIL));
var_dump(filter_var("user.name@example.com", FILTER_VALIDATE_EMAIL));

// FILTER_VALIDATE_URL
var_dump(filter_var("https://example.com", FILTER_VALIDATE_URL));
var_dump(filter_var("http://example.com/path?q=1", FILTER_VALIDATE_URL));
var_dump(filter_var("ftp://example.com", FILTER_VALIDATE_URL));
var_dump(filter_var("not-a-url", FILTER_VALIDATE_URL));
var_dump(filter_var("://example.com", FILTER_VALIDATE_URL));
var_dump(filter_var("javascript:alert(1)", FILTER_VALIDATE_URL));

// FILTER_VALIDATE_BOOLEAN
var_dump(filter_var("true", FILTER_VALIDATE_BOOLEAN));
var_dump(filter_var("false", FILTER_VALIDATE_BOOLEAN));
var_dump(filter_var("1", FILTER_VALIDATE_BOOLEAN));
var_dump(filter_var("0", FILTER_VALIDATE_BOOLEAN));
var_dump(filter_var("yes", FILTER_VALIDATE_BOOLEAN));
var_dump(filter_var("no", FILTER_VALIDATE_BOOLEAN));
var_dump(filter_var("on", FILTER_VALIDATE_BOOLEAN));
var_dump(filter_var("off", FILTER_VALIDATE_BOOLEAN));
var_dump(filter_var("maybe", FILTER_VALIDATE_BOOLEAN));
var_dump(filter_var(true, FILTER_VALIDATE_BOOLEAN));
var_dump(filter_var(0, FILTER_VALIDATE_BOOLEAN));

// FILTER_SANITIZE_*
echo filter_var("hello<script>", FILTER_SANITIZE_SPECIAL_CHARS), "\n";
echo filter_var("a@b@c", FILTER_SANITIZE_EMAIL), "\n";

// http_build_query nested
print_r(["a" => 1, "b" => ["x" => 1, "y" => 2]]);
echo http_build_query(["a" => 1, "b" => ["x" => 1, "y" => 2]]), "\n";
echo http_build_query(["arr" => [10, 20, 30]]), "\n";
echo http_build_query(["deep" => ["a" => ["b" => ["c" => 1]]]]), "\n";
echo http_build_query(["mix" => [1, "x" => "y", 3]]), "\n";

// parse_str with arrays
parse_str("a[]=1&a[]=2&a[]=3", $r);
print_r($r);
parse_str("user[name]=Alice&user[age]=30", $r);
print_r($r);
parse_str("nest[a][b][c]=deep", $r);
print_r($r);
parse_str("a[]=1&a[2]=x&a[]=3", $r);
print_r($r);

// json_encode INF/NAN
echo var_export(json_encode(INF), true), "\n";   // false
echo var_export(json_encode(-INF), true), "\n";  // false
echo var_export(json_encode(NAN), true), "\n";   // false
echo json_encode(INF, JSON_PARTIAL_OUTPUT_ON_ERROR) ?: "false", "\n"; // PHP outputs 0

// json_decode incomplete
var_dump(json_decode('{"a":')); // null
var_dump(json_decode('[1, 2,'));
var_dump(json_decode('{"a": "x'));
var_dump(json_decode(''));
var_dump(json_last_error());
echo json_last_error_msg(), "\n";

// json_decode trailing content
var_dump(json_decode('{} extra'));
var_dump(json_last_error_msg());

// array_walk on string keys
$a = ["a" => 1, "b" => 2, "c" => 3];
array_walk($a, function(&$v, $k) { $v = "$k=$v"; });
print_r($a);

// array_combine empty
print_r(array_combine([], []));

// array_combine error message
try { array_combine([1, 2], [1, 2, 3]); } catch (\ValueError $e) { echo $e->getMessage(), "\n"; }

// array_pad return
$a = [1, 2, 3];
$padded = array_pad($a, 5, 0);
print_r($a); // unchanged
print_r($padded);
