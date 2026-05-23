<?php
// generators now release their persistent locals on close (unset, foreach
// break, end of life). previously the locals were retained on init and only
// released at end-of-request, so __destruct was deferred for any object
// the generator held even after the consumer dropped the generator.
class T
{
    public $id;
    public function __construct($id) { $this->id = $id; }
    public function __destruct() { echo "destruct {$this->id}\n"; }
}

echo "== unset closes generator ==\n";
function gen1() {
    $local = new T('local1');
    yield 1;
    yield 2;
}
$g = gen1();
foreach ($g as $v) {
    if ($v == 1) break;
}
echo "before unset\n";
unset($g);
echo "after unset\n";

echo "== exhausted generator ==\n";
function gen3() {
    $local = new T('local3');
    yield 'x';
}
$g = gen3();
foreach ($g as $_) {}
echo "after foreach exhaust\n";
unset($g);
echo "after unset exhausted\n";
