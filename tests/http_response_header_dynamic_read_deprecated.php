<?php
// a variable-variable read whose name is known while compiling
// (`${'http_response_header'}`, `${__FUNCTION__}`) deprecates
// $http_response_header as a plain read does; a name known only at run time
// doesn't
error_reporting(E_ALL);
set_error_handler(function ($no, $msg, $file, $line) {
    echo "E$no line $line: $msg\n";
    return true;
});
$file = sys_get_temp_dir() . '/zphp_http_response_header_' . getmypid() . '.php';
file_put_contents($file, '<?php
function http_response_header() {
    ${__FUNCTION__} = "OK";
    var_dump(${__FUNCTION__});
    var_dump(isset(${"http_response_header"}));
    var_dump(${"http_response_header"});
    $n = "http_response_header";
    var_dump($$n);
}
http_response_header();
');
include $file;
unlink($file);
