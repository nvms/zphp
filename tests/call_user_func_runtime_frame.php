<?php
// php compiles a call_user_func it can name at compile time into a direct
// call, so the callee looks called from the script; one reached through a
// namespace's fallback or a dynamic call is an internal function with a
// frame of its own
namespace Foo;

function f() { throw new \Exception("x"); }
function show(\Throwable $e) {
    echo str_replace(__FILE__, 'FILE', $e->getTraceAsString()), "\n";
}

try { call_user_func(function () { f(); }); } catch (\Exception $e) { show($e); }
try { \call_user_func(function () { f(); }); } catch (\Exception $e) { show($e); }
try { call_user_func_array(function () { f(); }, []); } catch (\Exception $e) { show($e); }
try { \call_user_func_array(function () { f(); }, []); } catch (\Exception $e) { show($e); }
$name = 'call_user_func';
try { $name(function () { f(); }); } catch (\Exception $e) { show($e); }

set_error_handler(function ($type, $msg) { throw new \Exception($msg); });
try { call_user_func(function (array &$ref) {}, 'x'); } catch (\Exception $e) { show($e); }
try { \call_user_func(function (array &$ref) {}, 'x'); } catch (\Exception $e) { show($e); }
