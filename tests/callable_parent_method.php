<?php
// a callable naming a class for its method ([$this, "Base::m"],
// [$this, "parent::m"]) calls that class's method even where the object's
// own class overrides it

class Base
{
    public function __construct($msg)
    {
        echo __METHOD__, "($msg)\n";
    }

    public function greet($who)
    {
        return "Base greets $who";
    }
}

class Child extends Base
{
    public function __construct(...$args)
    {
        call_user_func_array([$this, 'Base::__construct'], $args);
        call_user_func_array([$this, 'parent::__construct'], $args);
        call_user_func_array('parent::__construct', $args);
        call_user_func_array(['parent', '__construct'], $args);
        call_user_func_array(['Base', '__construct'], $args);
    }

    public function greet($who)
    {
        return "Child greets $who";
    }

    public function viaParent()
    {
        echo call_user_func([$this, 'parent::greet'], 'a'), "\n";
        echo call_user_func([$this, 'Base::greet'], 'b'), "\n";
        echo implode(",", array_map([$this, 'Base::greet'], ['c'])), "\n";
        echo call_user_func([$this, 'greet'], 'd'), "\n";
        // a dynamic call doesn't take the class-qualified form
        $f = [$this, 'parent::greet'];
        try {
            echo $f('e'), "\n";
        } catch (Error $e) {
            echo $e->getMessage(), "\n";
        }
    }
}

$c = new Child('x');
$c->viaParent();
echo call_user_func([$c, 'Base::greet'], 'outside'), "\n";
