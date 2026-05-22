<?php
// regression: __destruct fires at the correct time (object refcounting).
// covers the cases zphp's Stage 1 refcounting supports - bare statements,
// function-scope locals, constructors, reassignment, method receivers,
// object arguments, object trees, and unset. output must match PHP exactly.

class R {
    public function __construct(public string $id) {}
    public function __destruct() { echo "~{$this->id}\n"; }
    public function touch() { return $this->id; }
}

// bare statement: a constructor-less-use temporary destructs immediately
echo "a\n";
new R("bare");
echo "b\n";

// function-scope local: destructs when the function returns
function makeLocal() {
    $r = new R("local");
    echo "  in makeLocal\n";
}
makeLocal();
echo "c\n";

// reassignment: the old object destructs when the variable is overwritten
$x = new R("first");
$x = new R("second");
echo "d\n";
$x = null;
echo "e\n";

// object passed as an argument, including a temporary
function consume(R $r) { echo "  consume {$r->touch()}\n"; }
consume(new R("arg-temp"));
echo "f\n";

// object held in a property, released on overwrite
class Box { public $item; }
$box = new Box();
$box->item = new R("prop-first");
$box->item = new R("prop-second");
echo "g\n";

// object tree: a parent destructs, then its children cascade
function makeTree() {
    $parent = new Box();
    $parent->item = new R("child");
    echo "  tree built\n";
}
makeTree();
echo "h\n";

// unset releases immediately
$u = new R("unset-me");
unset($u);
echo "i\n";

$box2 = new Box();
$box2->item = new R("unset-prop");
unset($box2->item);
echo "j\n";

// objects still live at the end destruct during shutdown
$kept = new R("kept-global");
echo "k\n";
