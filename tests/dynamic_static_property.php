<?php
// regression: dynamic static property access. Class::$$var and Class::${expr}
// (and the same with a dynamic class name) previously failed to parse. they
// resolve a static property whose name comes from a runtime expression.
class Model {
    public static $table = 'models';
    public static $conn = 'default';
}

$prop = 'table';

// read: literal class, dynamic property name
echo Model::${$prop}, "\n";
echo Model::$$prop, "\n";

// read: dynamic class, dynamic property name
$cls = 'Model';
echo $cls::${$prop}, "\n";
echo $cls::$$prop, "\n";

// read: dynamic class, literal property name still works
echo $cls::$conn, "\n";

// write: literal class, dynamic property name
Model::${$prop} = 'users';
echo Model::$table, "\n";
Model::$$prop = 'accounts';
echo Model::$table, "\n";

// write: dynamic class, dynamic property name
$cls::${$prop} = 'sessions';
echo Model::$table, "\n";

// the assignment expression yields the assigned value
echo (Model::${$prop} = 'final'), "\n";

// static:: with a dynamic property name inside a method, late static binding
class Base {
    public static $label = 'base';
    public function read(string $n) { return static::${$n}; }
    public function write(string $n, $v): void { static::${$n} = $v; }
}
class Derived extends Base {
    public static $label = 'derived';
}
$d = new Derived;
echo $d->read('label'), "\n";
$d->write('label', 'updated');
echo Derived::$label, "\n";

// inherited static property reached through a dynamic name
class Child extends Model {}
$f = 'conn';
echo Child::${$f}, "\n";
