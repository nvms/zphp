<?php
// self::class in a global constant's expression resolves against the
// running scope, and without one is zend_ast_evaluate's error

class Test
{
    public function foobar()
    {
        eval('const FOO = self::class; var_dump(FOO);');
    }
}
(new Test)->foobar();

class Child extends Test
{
    public function viaParent()
    {
        eval('const VIA_PARENT = parent::class; var_dump(VIA_PARENT);');
    }
}
(new Child)->viaParent();

try {
    eval('const BAR = self::class;');
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
try {
    eval('const BAZ = parent::class;');
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
var_dump(defined('BAR'), defined('BAZ'));

