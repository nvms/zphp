<?php
// JSON_PRETTY_PRINT
echo json_encode(['a' => 1, 'b' => [1,2], 'c' => ['x' => 'y']], JSON_PRETTY_PRINT), "\n";
echo json_encode([], JSON_PRETTY_PRINT), "\n";
echo json_encode(new stdClass, JSON_PRETTY_PRINT), "\n";

// JSON_UNESCAPED_UNICODE
echo json_encode(['name' => 'héllo wörld 日本'], JSON_UNESCAPED_UNICODE), "\n";
echo json_encode(['name' => 'héllo wörld 日本']), "\n";

// JSON_THROW_ON_ERROR
try {
    json_decode('invalid', true, 512, JSON_THROW_ON_ERROR);
} catch (\JsonException $e) {
    echo "caught: ", $e->getMessage(), "\n";
}

// json_decode depth limit (PHP allows up to depth-1 nested levels)
$nested = '[' . str_repeat('[', 5) . str_repeat(']', 5) . ']';
var_dump(json_decode($nested, false, 3) === null);  // too shallow
echo json_last_error_msg(), "\n";
var_dump(json_decode($nested, false, 7) !== null);  // ok
var_dump(json_decode($nested, false, 100) !== null); // ok

// array_reverse with preserve_keys
print_r(array_reverse([1, 2, 3]));               // reindex
print_r(array_reverse([1, 2, 3], true));         // [2=>3, 1=>2, 0=>1]
print_r(array_reverse(['a'=>1, 'b'=>2, 'c'=>3])); // string keys preserved
print_r(array_reverse([10=>'a', 20=>'b']));       // reindex by default
print_r(array_reverse([10=>'a', 20=>'b'], true)); // preserve

// array_merge int key handling
print_r(array_merge([1, 2], [3, 4]));            // reindex
print_r(array_merge(['a' => 1], ['b' => 2]));    // preserve string
print_r(array_merge([5 => 'a'], [3 => 'b']));    // ints reindex
print_r(array_merge(['a' => 1], ['a' => 2]));    // overwrite

// base64_decode whitespace allowed in both modes
var_dump(base64_decode(" a G V s b G 8 ="));
var_dump(base64_decode(" a G V s b G 8 =", true));

// hash raw_output
echo bin2hex(hash('md5', 'hello', true)), "\n";
echo hash('md5', 'hello', false), "\n";
echo bin2hex(hash('sha256', 'hello', true)), "\n";

// fnmatch character classes
var_dump(fnmatch("[abc]bc", "abc"));
var_dump(fnmatch("[!abc]bc", "abc"));
var_dump(fnmatch("[a-z]bc", "xbc"));
