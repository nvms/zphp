<?php
// the engine calls the exception handler once the script stopped: the
// deprecation for a #[\Deprecated] handler names no file or line
error_reporting(E_ALL);
set_error_handler(function ($no, $message, $file, $line) {
    echo "error: $message in ", basename($file), ":$line\n";
    return true;
});

#[\Deprecated]
function handler($e) {
    echo "handled: ", $e->getMessage(), "\n";
}

#[\Deprecated]
function called() {
}

called();
set_exception_handler('handler');
throw new Exception('test');
