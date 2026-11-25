<?php
// php://filter counts the filters already on the stream, so a resource that
// is itself a php://filter url adds to the same limit
set_error_handler(function ($no, $msg) { echo "error $no: $msg\n"; return true; });
function nested($n, $resource) {
    return str_repeat("php://filter/string.toupper/resource=", $n) . $resource;
}
var_dump(file_get_contents(nested(16, 'data:text/plain,sixteen')));
var_dump(file_get_contents(nested(17, 'data:text/plain,seventeen')));
var_dump(file_get_contents(nested(18, 'data:text/plain,eighteen')));
$ctx = stream_context_create(['filter' => ['max_filter_count' => 2]]);
var_dump(file_get_contents(nested(3, 'data:text/plain,three'), false, $ctx));
var_dump(file_get_contents(nested(2, 'data:text/plain,two'), false, $ctx));
var_dump(file_get_contents('php://filter/string.rot13|string.toupper/resource=' . nested(15, 'data:text/plain,mixed')));
