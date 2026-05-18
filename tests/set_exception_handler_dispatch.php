<?php
// regression: when interpret() unwinds with a pending exception and a user
// exception handler is installed, dispatch to that handler before falling
// back to the 'Uncaught Exception:' formatter. previously zphp ignored
// user_exception_handler at the top level and always printed the fatal
set_exception_handler(function($e) {
    echo "handler1: " . get_class($e) . " " . $e->getMessage() . " code=" . $e->getCode() . "\n";
});
throw new RuntimeException("from script", 7);
