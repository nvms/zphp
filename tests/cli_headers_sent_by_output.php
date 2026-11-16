<?php
// the cli sends its headers with the first output: header functions then
// refuse with php's warnings, and the cli keeps no header list
set_error_handler(function ($no, $msg) {
    // the position of the output that sent them differs between runs
    echo "warning: ", preg_replace('/\(output started at .*\)/', '(output started at X)', $msg), "\n";
    return true;
});
var_dump(http_response_code());
header("X-Test: 1");
var_dump(headers_list());
var_dump(http_response_code(201));
var_dump(http_response_code(202));
var_dump(http_response_code());
var_dump(headers_sent());
var_dump(header("X-Late: 1"));
var_dump(header_remove("X-Test"));
var_dump(setcookie("a", "b"));
var_dump(setrawcookie("a", "b"));
var_dump(http_response_code(500));
var_dump(http_response_code());
var_dump(headers_sent($file, $line), $line > 0);
