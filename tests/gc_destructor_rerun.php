<?php
// a collection that finds garbage with destructors calls them and frees the
// rest of the garbage in the same run; what the destructors' objects reach
// waits for the run php starts again once, whose destructors run too

class C {
    public function __destruct() { echo "C destructor\n"; }
}
$t = [new C];
$t[] = &$t;
unset($t);
var_dump(gc_collect_cycles());
var_dump(gc_collect_cycles());

class Node {
    public $self;
    public function __construct(public string $name) { $this->self = $this; }
    public function __destruct() {
        echo "destroying {$this->name}\n";
        if ($this->name === 'first') new Node('made by first');
        if ($this->name === 'made by first') new Node('made by second');
    }
}

new Node('first');
echo "collect\n";
var_dump(gc_collect_cycles());
echo "collect again\n";
var_dump(gc_collect_cycles());
echo "done\n";
