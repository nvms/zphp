<?php
// a stream operation's own errors wait for the operation to end, so what
// the code it runs raises meanwhile (a user wrapper's warning) comes first
set_error_handler(function ($no, $msg) { echo "warning: $msg\n"; return true; });
class Noisy {
    public $context;
    function stream_open($path, $mode, $options, &$opened_path): bool { return true; }
    function stream_cast(int $as) {
        trigger_error("cast called", E_USER_WARNING);
        return false;
    }
    function stream_read(int $count): string|false { return ""; }
    function stream_eof(): bool { return true; }
}
stream_wrapper_register('noisy', Noisy::class);
$a = fopen('noisy://a', 'r');
$b = fopen('noisy://b', 'r');
$read = [$a, $b];
$write = null;
$except = null;
try {
    var_dump(stream_select($read, $write, $except, 0));
} catch (Throwable $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
