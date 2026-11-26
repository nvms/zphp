<?php
// a read of a dimension or property chain runs the keys that need code
// first and then the fetches (zend_delayed_compile_dim/prop): a plain
// variable base is read by the first fetch
set_error_handler(function ($no, $msg) {
    echo "warning: $msg\n";
    return true;
});
function k($n) { echo "key $n\n"; return $n; }

$r = $undef[k(1)][k(2)];
$r = $undefObj->{k('a')}->{k('b')};
$r = $mixed[k(3)]->{k('c')}[k(4)];
var_dump(strlen($undefArg[k(5)] ?? ''));
var_dump($undefDump[k(6)]);
echo $undefEcho[k(7)][0], "\n";

// a key that reassigns the base is seen by the fetch
$a = [1, 2, 3];
echo $a[($a = [7, 8, 9]) ? 1 : 0], "\n";
$i = 0;
echo $a[$i + 2], $a[$i], "\n";

// a base that is a call runs before the keys, the fetches after them all
function arr() { echo "arr()\n"; return ['x' => ['y' => 'found']]; }
echo arr()[k('x')][k('y')], "\n";
echo arr()[k('missing')][k('y')] ?? 'none', "\n";

class Box {
    public $items = ['p' => ['q' => 'deep']];
    public static $shared = ['s' => 'static'];
    public function get() { return $this->items[k('p')][k('q')]; }
    public function chain() { return $this; }
}
$box = new Box;
echo $box->get(), "\n";
echo $box->chain()->items[k('p')][k('q')], "\n";
echo Box::$shared[k('s')], "\n";
$name = 'items';
echo $box->$name[k('p')]['q'], "\n";
echo $box->{k('items')}[k('p')]['q'], "\n";
