<?php
// class_alias() registers the class itself under another name: objects,
// called classes, instanceof and static state are the original class's

class Original {
    public static $count = 0;
    public function __construct() {
        static::$count++;
        echo "constructed ", get_called_class(), "\n";
    }
    public static function make() {
        return new static;
    }
    public static function who() {
        echo static::class, "\n";
    }
}

interface Shape {}
abstract class Base {}

var_dump(class_alias('Original', 'Alias'));
var_dump(class_alias('Shape', 'ShapeAlias'));
var_dump(class_alias('Base', 'BaseAlias'));

$a = new Alias;
var_dump($a);
echo get_class($a), "\n";
var_dump($a instanceof Alias, $a instanceof Original);
var_dump(new Original instanceof Alias);
var_dump(Alias::make() instanceof Original);
Alias::who();
echo Alias::$count, " ", Original::$count, "\n";
Alias::$count = 10;
echo Original::$count, "\n";

$name = 'alias';
var_dump(new $name);

var_dump(is_subclass_of(new Original, 'Alias'));
var_dump(is_a(new Original, 'Alias'));
var_dump(get_parent_class(new Alias));

class Child extends Alias {}
var_dump(get_parent_class(new Child));
var_dump(new Child instanceof Alias);
var_dump(is_subclass_of(new Child, 'Alias'));

class Square implements ShapeAlias {}
var_dump(new Square instanceof Shape, new Square instanceof ShapeAlias);
var_dump(class_implements(new Square));

function takes(Alias $x): Original { return $x; }
var_dump(get_class(takes(new Original)));

try {
    new BaseAlias;
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
$abstract = 'BaseAlias';
try {
    new $abstract;
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}

$r = new ReflectionClass('Alias');
echo $r->getName(), "\n";

var_dump(class_exists('Alias'), class_exists('alias'), interface_exists('ShapeAlias'));
var_dump(class_alias('Original', 'Alias'));
var_dump(class_alias('Missing', 'Other'));
var_dump(class_alias('stdClass', 'Std'));
var_dump(new Std);
echo serialize(new Alias), "\n";
var_dump(unserialize('O:5:"Alias":0:{}'));
