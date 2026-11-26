<?php
// a variable-variable name converts as a string: __toString runs and may
// throw, an array warns
class BadStr { public function __toString() { throw new Exception("bad"); } }
class Name { public function __toString() { return "v"; } }
$bad = new BadStr;
$name = new Name;
${""} = 42;
try { unset(${$bad}); } catch (Throwable $e) { echo "unset: ", $e->getMessage(), "\n"; }
var_dump(${""});
try { $x = ${$bad}; } catch (Throwable $e) { echo "read: ", $e->getMessage(), "\n"; }
try { $x = isset(${$bad}); } catch (Throwable $e) { echo "isset: ", $e->getMessage(), "\n"; }
try { ${$bad} = 1; } catch (Throwable $e) { echo "write: ", $e->getMessage(), "\n"; }
try { ${$bad}[] = 1; } catch (Throwable $e) { echo "dim write: ", $e->getMessage(), "\n"; }
var_dump(${""});
${$name} = 5;
var_dump($v, ${$name}, isset(${$name}));
unset($v);
${$name}[] = 1;
var_dump($v);
unset(${$name});
var_dump(isset($v));
${1}[] = 2;
var_dump(${'1'});

function f() {
    $b = new BadStr;
    $n = new Name;
    try { unset(${$b}); } catch (Throwable $e) { echo "f unset: ", $e->getMessage(), "\n"; }
    try { $x = ${$b}; } catch (Throwable $e) { echo "f read: ", $e->getMessage(), "\n"; }
    ${$n} = 'local';
    var_dump($v);
}
f();
