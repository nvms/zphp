<?php
// ReflectionAttribute's private constructor parses no parameters: called
// through reflection with any arguments it refuses with its own message
#[Attribute]
class A {}
class Foo {
    #[A]
    public function bar() {}
}
$attribute = (new ReflectionMethod(Foo::class, "bar"))->getAttributes()[0];
$rm = new ReflectionMethod($attribute, "__construct");
foreach ([[], [0, 1, 2]] as $args) {
    try {
        var_dump($rm->invokeArgs($attribute, $args));
    } catch (ReflectionException $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
