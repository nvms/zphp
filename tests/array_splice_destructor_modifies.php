<?php
// array_splice whose result is unused frees the removed elements during the
// splice; a destructor that then changes or drops the array is an Error
// (php-src gh16649). a by-reference array argument is separated only when
// something else holds the array

class Writes {
    public function __construct(public string $how) {}
    public function __destruct() {
        global $arr;
        echo "destruct {$this->how}\n";
        switch ($this->how) {
            case 'append': $arr[] = 0; break;
            case 'null': $arr = null; break;
            case 'string key': $arr['str'] = 0; break;
            case 'nothing': break;
        }
    }
}

foreach (['append', 'null', 'string key', 'nothing'] as $how) {
    $arr = ['1', new Writes($how), '2'];
    try {
        array_splice($arr, 1, 1);
        echo "spliced\n";
    } catch (Error $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
}

// the result in use keeps the removed elements alive: no destructor runs
$arr = ['1', new Writes('append'), '2'];
$removed = array_splice($arr, 1, 1);
echo "spliced with result\n";
unset($removed);
var_dump($arr);

$arr = ['a', new Writes('append'), 'b'];
try {
    array_splice($arr, 1, 1, ['replacement']);
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}

class Quiet {
    public function __construct(public string $name) {}
    public function __destruct() { echo "destruct {$this->name}\n"; }
}

$list = ['1', new Quiet('plain'), '2'];
array_splice($list, 1, 1);
echo "after plain\n";

$list = ['1', new Quiet('global'), '2'];
function touchList() { global $list; }
touchList();
array_splice($list, 1, 1);
echo "after global\n";

function referenced() {
    $a = ['1', new Quiet('referenced'), '2'];
    $b = &$a;
    array_splice($a, 1, 1);
    echo "after referenced\n";
}
referenced();

$a = [];
array_unshift($a, '');
array_unshift($a, $a);
var_dump($a);
function f($x, $y) { var_dump($x); }
$a = [3, 1, 2];
f($a, sort($a));
var_dump($a);
$a = [3, 1, 2];
$r = [$a, sort($a)];
var_dump($r);
$a = [3, 1, 2];
echo implode(',', $a) . (sort($a) ? implode(',', $a) : '') . "\n";
