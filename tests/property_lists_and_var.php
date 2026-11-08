<?php
// `var` declares a public property, and one declaration may list several
// properties sharing its modifiers and type
class Legacy {
    var $name = 'legacy';
    var $tags, $notes = 'none';
    var ?int $count = null;
    public $a, $b = 2, $c;
    protected static int $first = 1, $second = 2;
    private readonly string $left, $right;
    public function __construct() { $this->left = 'L'; $this->right = 'R'; }
    public function all() { return [$this->left, $this->right, self::$first, self::$second]; }
}
var_dump(new Legacy, (new Legacy)->all());
foreach (['name', 'tags', 'notes', 'count', 'b', 'second', 'right'] as $prop) {
    $p = new ReflectionProperty('Legacy', $prop);
    echo $prop, ': ', implode(' ', Reflection::getModifierNames($p->getModifiers())), ' ', $p->getType() ?? '-', "\n";
}
trait Bag { var $x, $y = 'y'; }
class UsesBag { use Bag; }
var_dump(new UsesBag);
