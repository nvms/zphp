<?php
// gc_collect_cycles() counts as php's collector does when garbage has
// destructors: they run first, and what is garbage after them is freed and
// counted by the run that follows; roots their code makes wait for it

class Foo {
    public $bar;
    public function __destruct() {
        if ($this->bar !== null) unset($this->bar);
    }
}
class Bar {
    public $foo;
    public function __destruct() {
        if ($this->foo !== null) unset($this->foo);
    }
}
$foo = new Foo();
$bar = new Bar();
$foo->bar = $bar;
$bar->foo = $foo;
unset($foo, $bar);
var_dump(gc_collect_cycles());

class Node {
    public $name;
    public $children;
    public $parent;
    public function __construct($name) { $this->name = $name; }
    public function insert($node) {
        $node->parent = $this;
        $this->children[] = $node;
    }
    public function __destruct() {
        echo "destroy {$this->name}\n";
        unset($this->name, $this->children, $this->parent);
    }
}
$a = new Node('A');
$b = new Node('B');
$c = new Node('C');
$a->insert($b);
$a->insert($c);
unset($a, $b, $c);
var_dump(gc_collect_cycles());

class Nested {
    public $self;
    public function __destruct() {
        $cycle = [];
        $cycle[] = &$cycle;
        unset($cycle);
        echo "inner run: ", gc_collect_cycles(), "\n";
    }
}
$n = new Nested();
$n->self = $n;
unset($n);
var_dump(gc_collect_cycles());

$out = new stdClass;
$out->x = $out;
parse_str("a=b", $out);
var_dump(gc_collect_cycles());
