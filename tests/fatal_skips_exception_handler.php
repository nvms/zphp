<?php
// a fatal error is not a throwable: the exception handler never sees it,
// shutdown functions still run
set_exception_handler(function ($e) { echo "handler: ", $e->getMessage(), "\n"; });
register_shutdown_function(function () { echo "shutdown\n"; });
class Base { public function m() {} }
echo "declaring\n";
if (true) {
    class Narrower extends Base { private function m() {} }
}
echo "not reached\n";
