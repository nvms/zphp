<?php
// while the exception handler runs it sits on the handler stack, so
// restoring inside it reaches the handlers below; afterwards the top of the
// stack is installed again unless the handler installed another
function first(Throwable $e) { echo 'first: ', $e->getMessage(), "\n"; }
function second(Throwable $e) {
    echo 'second: ', $e->getMessage(), "\n";
    restore_exception_handler();
    var_dump(get_exception_handler());
    restore_exception_handler();
    var_dump(get_exception_handler());
}
set_exception_handler('first');
set_exception_handler('second');
register_shutdown_function(function () {
    var_dump(get_exception_handler());
    var_dump(set_exception_handler(null));
});
throw new RuntimeException('boom');
