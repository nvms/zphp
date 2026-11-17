<?php
// an argument TypeError names an anonymous class's method by the class name
// alone (php cuts the "Class::method" string at the name's NUL); the return
// type error names both
$a = new class {
    public function testParam(self|string $a) {}
    public function intParam(int $i) {}
    public function test(): self|string { return new stdClass; }
};
foreach ([fn() => $a->testParam(null), fn() => $a->intParam([]), fn() => $a->test()] as $call) {
    try {
        $call();
    } catch (TypeError $e) {
        echo preg_replace('/called in .*/', 'called in ...', $e->getMessage()), "\n";
    }
}
class Named { public function m(int $i) {} }
try {
    (new Named)->m("x");
} catch (TypeError $e) {
    echo preg_replace('/called in .*/', 'called in ...', $e->getMessage()), "\n";
}
