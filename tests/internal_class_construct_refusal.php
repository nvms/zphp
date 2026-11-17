<?php
// the internal classes only their functions instantiate have no constructor;
// new and reflection refuse them

foreach (['Directory', 'CurlHandle', 'CurlMultiHandle', 'CurlShareHandle', 'DeflateContext', 'InflateContext', 'XMLParser', 'GdImage'] as $class) {
    $r = new ReflectionClass($class);
    echo $class, ": constructor ", var_export($r->getConstructor(), true), "\n";
    try {
        new $class();
    } catch (Error $e) {
        echo "  new: ", $e->getMessage(), "\n";
    }
    try {
        $r->newInstance();
    } catch (Error $e) {
        echo "  newInstance: ", $e->getMessage(), "\n";
    }
    try {
        echo "  without constructor: ", get_class($r->newInstanceWithoutConstructor()), "\n";
    } catch (ReflectionException $e) {
        echo "  without constructor: ", $e->getMessage(), "\n";
    }
}

try {
    new Directory();
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}

$d = dir(__DIR__);
echo get_class($d), "\n";
$d->close();

foreach ((new ReflectionClass('Directory'))->getMethods() as $m) echo $m->name, "\n";
print_r(get_class_methods('Directory'));
