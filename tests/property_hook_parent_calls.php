<?php
// parent::$prop::get() and ::set() in a property hook call the parent's
// hook, or reach the parent property's storage when it has none; hooks are
// named "$prop::get" as php names them
class Base {
    public int $hooked {
        get => 40;
        set { echo "Base set $value\n"; }
    }
    public $plain = 'plain';
    private $hidden;
}
class Child extends Base {
    public int $hooked {
        get => parent::$hooked::GET() + 2;
        set { parent::$hooked::set($value * 2); }
    }
    public $plain {
        get => strtoupper(parent::$plain::get());
        set => var_dump(parent::$plain::set($value . '!'));
    }
    public $hidden {
        get => parent::$hidden::get();
    }
    public $extra {
        get { var_dump(__FUNCTION__, __METHOD__); return 1; }
    }
}
class Orphan {
    public $prop { get => parent::$prop::get(); }
}
class Holder { public static $cls = 'Target'; }
class Target { static function get() { return 'static call on a value'; } }
class Sub extends Holder { static function run() { return (parent::$cls)::get(); } }

$c = new Child;
var_dump($c->hooked);
$c->hooked = 5;
var_dump($c->plain);
$c->plain = 'set';
var_dump($c->plain);
$c->extra;
foreach ([fn () => $c->hidden, fn () => (new Orphan)->prop] as $f) {
    try { $f(); } catch (Error $e) { echo $e->getMessage(), "\n"; }
}
echo Sub::run(), "\n";
class Strict { public int $n { get => 'not an int'; } }
try { (new Strict)->n; } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
