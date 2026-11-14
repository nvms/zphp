<?php
// zend.exception_ignore_args and zend.exception_string_param_max_len set at run time

function fail(string $secret, int $n) {
    throw new RuntimeException("failed");
}

function show(Throwable $e) {
    foreach ($e->getTrace() as $i => $frame) {
        echo $i, ": ", $frame['function'], " args: ", array_key_exists('args', $frame) ? count($frame['args']) : "none", "\n";
    }
    echo preg_replace('/^#(\d+) .*?: /m', '#$1 ', $e->getTraceAsString()), "\n";
}

var_dump(ini_get('zend.exception_ignore_args'));
var_dump(ini_get('zend.exception_string_param_max_len'));

try { fail("a long secret string", 1); } catch (Exception $e) { show($e); }

var_dump(ini_set('zend.exception_ignore_args', '1'));
try { fail("a long secret string", 2); } catch (Exception $e) { show($e); }
$f = function ($x) { return new LogicException("made"); };
show($f("value"));
var_dump(ini_set('zend.exception_ignore_args', '0'));

var_dump(ini_set('zend.exception_string_param_max_len', '5'));
try { fail("a long secret string", 3); } catch (Exception $e) { show($e); }
var_dump(ini_set('zend.exception_string_param_max_len', '0'));
try { fail("abc", 4); } catch (Exception $e) { show($e); }
var_dump(ini_set('zend.exception_string_param_max_len', '-1'));
var_dump(ini_set('zend.exception_string_param_max_len', '1000001'));
var_dump(ini_get('zend.exception_string_param_max_len'));
var_dump(ini_set('zend.exception_string_param_max_len', '1000000'));
try { fail(str_repeat("x", 40), 5); } catch (Exception $e) { show($e); }
ini_restore('zend.exception_string_param_max_len');
try { fail(str_repeat("y", 40), 6); } catch (Exception $e) { show($e); }
