<?php
// the deprecation of a #[\Deprecated] exception handler is raised by the
// engine once the script is done: the error handler it calls is an
// [internal function] frame

function my_error_handler(int $errno, string $errstr, ?string $errfile = null, ?int $errline = null) {
	throw new \ErrorException($errstr, 0, $errno, $errfile, $errline);
}

set_error_handler('my_error_handler');

#[\Deprecated]
function my_exception_handler($e) {
	echo "Handled: ", $e->getMessage(), PHP_EOL;
};

set_exception_handler('my_exception_handler');

#[\Deprecated]
function test() {
}

test();

?>
