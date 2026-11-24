<?php
// php 8.6 no longer names a parameter in "func(param): ..." warnings; with
// error_include_args on, every such warning lists the call's arguments as a
// stack trace prints them
set_error_handler(function ($no, $msg) {
    echo "$no: $msg\n";
    return true;
});
$missing = sys_get_temp_dir() . '/zphp_no_such_' . 'file';
var_dump(ini_get('error_include_args'));
foreach ([false, true] as $on) {
    ini_set('error_include_args', $on ? '1' : '0');
    @rmdir('/zphp_no_such_dir');
    rmdir('/zphp_no_such_dir');
    unlink('/zphp_no_such_dir');
    fopen('/zphp_no_such_dir/x', 'r');
    file_get_contents('/zphp_no_such_dir/x');
    hex2bin('abc');
    password_hash('secret', PASSWORD_BCRYPT, ['salt' => str_repeat('a', 22), 'cost' => 4]);
    array_chunk([1], 1, true);
    str_repeat('x', 2) . ini_get('nope');
    mkdir('/zphp_no_such_dir/a/b');
}
try {
    new DirectoryIterator('/zphp_no_such_dir');
} catch (UnexpectedValueException $e) {
    echo $e->getMessage(), "\n";
}
// the arguments as argument parsing converted them
ini_set('error_include_args', '1');
@rename(-1, '/zphp_no_such_dir/x');
echo error_get_last()['message'], "\n";
@rename(true, '/zphp_no_such_dir/x');
echo error_get_last()['message'], "\n";
@file_get_contents(1.5);
echo error_get_last()['message'], "\n";
