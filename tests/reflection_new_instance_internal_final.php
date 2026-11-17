<?php
// newInstanceWithoutConstructor() refuses an internal final class whose
// objects have state of their own, and makes the plain ones
foreach (['Closure', 'Generator', 'WeakMap', 'FiberError', 'HashContext', 'Random\Randomizer', 'Random\Engine\Mt19937', 'ReflectionGenerator', '__PHP_Incomplete_Class', 'Attribute', 'SensitiveParameterValue', 'Override', 'stdClass', 'ArrayObject'] as $class) {
    try {
        $o = (new ReflectionClass($class))->newInstanceWithoutConstructor();
        echo $class, ": ", get_class($o), "\n";
    } catch (ReflectionException $e) {
        echo $e->getMessage(), "\n";
    }
}
foreach (['WeakMap', 'GMP', 'DOMException', 'CurlHandle', 'CurlMultiHandle', 'CurlShareHandle', 'XMLParser', 'GdImage', 'ReflectionFiber', 'ReflectionGenerator', 'Random\Randomizer', 'Random\Engine\Secure', 'Random\Engine\Xoshiro256StarStar', 'Random\Engine\PcgOneseq128XslRr64'] as $class) {
    echo $class, (new ReflectionClass($class))->isFinal() ? " is final\n" : " is not final\n";
}
