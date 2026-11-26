<?php
// while a class declaration loads its interfaces and parent, the class is
// in the class table unlinked: looking it up finds nothing and does not
// autoload it again
spl_autoload_register(function ($class) {
    echo "autoload $class\n";
    var_dump(class_exists('Child'));
    var_dump(class_exists('Child', false));
    try {
        new ReflectionClass('Child');
    } catch (ReflectionException $e) {
        echo $e->getMessage(), "\n";
    }
    if ($class === 'Contract') {
        eval('interface Contract {}');
    } elseif ($class === 'Base') {
        eval('class Base {}');
    }
});

class Child extends Base implements Contract {}
var_dump(class_exists('Child', false));
var_dump(new Child instanceof Contract);

// a parent no autoloader declares is looked for once
if (true) {
    class Orphan extends MissingParent implements Contract {}
}
