<?php
// Stage 2 element-overwrite release: array_pop / array_shift drop the array's
// retain on the displaced element so the popped object can __destruct when
// the result is discarded, rather than leaking until end-of-request. covers
// the bare single-element discarded-pop case; other patterns (multi-element,
// array literals, function-return arrays) still leak retains upstream of
// array_pop/shift, deferred to separate Stage 2 follow-ups.
class T
{
    public $id;
    public function __construct($i) { $this->id = $i; }
    public function __destruct() { echo "destruct {$this->id}\n"; }
}

echo "== array_pop (single, discarded) ==\n";
$arr = [];
$arr[] = new T('A');
array_pop($arr);
echo "after pop\n";

echo "== array_shift (single, discarded) ==\n";
$arr = [];
$arr[] = new T('B');
array_shift($arr);
echo "after shift\n";

