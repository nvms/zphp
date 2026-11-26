<?php
// a name an internal function's variadic can't take is passed and refused
// by the function, after its argument count check: the error comes from the
// function's frame, whose trace entry shows the named argument

function show(Throwable $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n", $e->getTraceAsString(), "\n";
}

try { call_user_func_array("array_multisort", ["" => 1]); } catch (Error $e) { show($e); }
try { call_user_func_array("array_multisort", [1, "x" => 1]); } catch (Error $e) { show($e); }
try { $a = [3, 1]; array_multisort($a, x: 1); } catch (Error $e) { show($e); }
try { max(1, 2, x: 1); } catch (Error $e) { show($e); }
try { max(x: 1); } catch (Error $e) { show($e); }
try { array_merge([1], x: [2]); } catch (Error $e) { show($e); }
try { (new ReflectionFunction('max'))->invokeArgs([1, 'y' => 2]); } catch (Error $e) { show($e); }
try { (new ReflectionFunction('max'))->invokeArgs(['y' => 2]); } catch (Error $e) { show($e); }
$f = 'max';
try { $f(1, 2, z: 3); } catch (Error $e) { show($e); }
try { $f(...['z' => 3]); } catch (Error $e) { show($e); }

// names a variadic takes still go through
function f($a, ...$rest) { throw new Exception("x"); }
try { f(1, foo: 2); } catch (Exception $e) { show($e); }
try { call_user_func_array('f', [1, 'foo' => 2]); } catch (Exception $e) { show($e); }
