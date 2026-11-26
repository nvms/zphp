<?php
// an element fetch is a link of a nullsafe chain: when the nullsafe
// operator short-circuits, the element isn't fetched

class Box {
    public $items = ['a' => ['b' => 'deep'], 'o' => null];
    public function get() { return ['k' => 'v']; }
    public function __toString(): string { return 'box'; }
}

function show($label, $value) {
    echo $label, ': ', var_export($value, true), "\n";
}

$n = null;
$box = new Box;

show('null prop dim', $n?->items['a']);
show('null prop dim dim', $n?->items['a']['b']);
show('null call dim', $n?->get()['k']);
show('null dim prop', $n?->items['a']->x);
show('box prop dim', $box?->items['a']['b']);
show('box call dim', $box?->get()['k']);
show('literal', (null)?->test['test']);
show('isset', isset($n?->items['a']));
show('coalesce', $n?->items['a'] ?? 'default');
show('box coalesce', $box?->items['missing'] ?? 'default');
show('empty', empty($n?->items['a']));
echo "interpolated: {$n?->items['a']}|\n";

// the index is evaluated only when the chain goes on
function idx() { echo "idx called\n"; return 'a'; }
show('index skipped', $n?->items[idx()]);
show('index run', $box?->items[idx()]['b']);

// an element of a short-circuited chain that is null still warns
show('null element', $box?->items['o']['x']);

const D = (null)?->test['test'];
show('constant', D);

class C {
    const X = (null)?->a['b'];
    public $p = (null)?->a['b']['c'];
}
show('class constant', C::X);
show('property default', (new C)->p);

function f($a = (null)?->a['b']) { return $a; }
show('parameter default', f());
