<?php
// header() emits PHP 'headers already sent' warnings post-output (architectural)

// session_status
echo session_status(), "\n"; // PHP_SESSION_NONE = 1
echo PHP_SESSION_DISABLED, ":", PHP_SESSION_NONE, ":", PHP_SESSION_ACTIVE, "\n";

// session_id (empty before start)
echo session_id() === "" ? "empty\n" : "set\n";

// opcache_* (skip - CLI usually disabled)
// opcache extension not in zphp (architectural)

// ob_start nested levels
echo ob_get_level(), "\n"; // 0 (or 1 if buffering on)
$initial = ob_get_level();
ob_start();
echo "outer";
ob_start();
echo "inner";
echo "/", ob_get_level() - $initial, "/"; // 2
$inner = ob_get_clean();
$outer = ob_get_clean();
echo "got: outer=$outer inner=$inner|levels=", ob_get_level() - $initial, "\n";

// ob_start with callback
ob_start(function ($buf) { return strtoupper($buf); });
echo "hello world";
$out = ob_get_clean();
echo $out, "\n";

// ob_start with chained callbacks
ob_start(function ($buf) { return "[" . $buf . "]"; });
ob_start(function ($buf) { return "(" . $buf . ")"; });
echo "x";
$inner = ob_get_clean();
echo "got:", $inner;
$outer = ob_get_clean();
echo " final:$outer\n";

// ob_get_contents (peek)
ob_start();
echo "abc";
$peek = ob_get_contents();
echo "def";
$flush = ob_get_clean();
echo "peek=[$peek] flush=[$flush]\n";

// ob_get_status
ob_start();
echo "test";
$status = ob_get_status();
echo gettype($status), ":", isset($status["level"]) || isset($status[0]) ? "has-level" : "no", "\n";
ob_end_clean();

// ob_get_status(true) returns all levels
ob_start();
ob_start();
$all = ob_get_status(true);
echo gettype($all), ":", count($all), "\n";
ob_end_clean();
ob_end_clean();

// ob_implicit_flush
ob_implicit_flush(true);
ob_implicit_flush(false);
echo "after\n";

// flush() - no error in CLI
flush();
echo "after-flush\n";

// ob_clean / ob_end_clean
ob_start();
echo "discard";
ob_clean();
echo "kept";
$out = ob_get_clean();
echo "result:[$out]\n";

// ob_end_flush sends to outer buffer
ob_start();
ob_start();
echo "inner";
ob_end_flush(); // sends "inner" to outer
$outer = ob_get_clean();
echo "outer:[$outer]\n"; // [inner]

// ob_list_handlers
ob_start();
$handlers = ob_list_handlers();
print_r($handlers);
ob_end_clean();

// ob_start("strtoupper") fails in PHP due to arity mismatch (architectural)

// php://output / php://input (skip - mostly stream stuff)
echo "done\n";
