<?php
// an object with __toString compares as its string against a string,
// also inside arrays and object properties (zend_compare)

class Text {
    public function __construct(private string $s) {}
    public function __toString(): string { return $this->s; }
}

$a = (object)['foo' => 'test', 'bar' => 2];
$b = (object)['foo' => new Text(''), 'bar' => 2];
var_dump($a > $b, $a < $b, $a == $b, $a <=> $b);
var_dump(['test'] > [new Text('')], ['x'] == [new Text('x')], [new Text('a')] <=> ['b']);
var_dump(in_array('x', [new Text('x')]), array_search('y', [1, new Text('y')]));
var_dump([new stdClass] == ['x']);

// releasing both operands from __toString leaves the comparison intact
$c = (object)['foo' => 'test', 'bar' => 2];
$d = (object)['foo' => new class {
    public function __toString() {
        global $c, $d;
        $c = $d = null;
        return '';
    }
}, 'bar' => 2];
var_dump($c > $d);
