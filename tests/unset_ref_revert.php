<?php
// unbinding the last alias of a reference must revert the referenced
// element/prop to a plain value, so later writes COW-separate normally

// foreach-by-ref leaves $it referencing the last element; unset($it) drops
// the reference - a value copy taken afterwards must not see later writes
$a = [0 => [1, 2]];
foreach ($a as &$it) {}
unset($it);
$b = $a[0];
$a[0][] = 3;
echo "t1: ", count($b), " ", count($a[0]), "\n";

// explicit element ref, then unset
$a2 = [0 => [1, 2]];
$r2 = &$a2[0];
unset($r2);
$b2 = $a2[0];
$a2[0][] = 3;
echo "t2: ", count($b2), " ", count($a2[0]), "\n";

// two aliases: unset of one keeps the reference alive through the other
$a3 = [0 => [1, 2]];
$r3 = &$a3[0];
$s3 = &$r3;
unset($r3);
$s3[] = 3;
echo "t3: ", count($a3[0]), "\n";

// object property ref, then unset
class P { public $p = ['k' => [1, 2]]; }
$o = new P();
$r4 = &$o->p;
unset($r4);
$b4 = $o->p;
$o->p['k2'] = 5;
echo "t4: ", count($b4), " ", count($o->p), "\n";

// unset of a by-ref param inside a function must not revert the caller's ref
function f5(&$x) { unset($x); }
$a5 = [0 => [1, 2]];
$r5 = &$a5[0];
f5($r5);
$r5[] = 3;
echo "t5: ", count($a5[0]), "\n";

// the WP_Hook resort pattern: iterate a property element with current/next
// while a mid-loop resort rebinds it via foreach-by-ref + unset. the second
// run must iterate from the start again
class H {
    public $iterations = [];
    public $priorities = [10, 20];

    public function resort() {
        $new = $this->priorities;
        foreach ($this->iterations as $i => &$iter) {
            $cur = current($iter);
            $iter = $new;
            while (current($iter) < $cur) {
                if (false === next($iter)) break;
            }
        }
        unset($iter);
    }

    public function run($label) {
        $this->iterations[0] = $this->priorities;
        $out = [];
        do {
            $pri = current($this->iterations[0]);
            $out[] = $pri;
            if ($pri === 10 && count($this->priorities) < 3) {
                $this->priorities[] = 30;
                $this->resort();
            }
        } while (false !== next($this->iterations[0]));
        unset($this->iterations[0]);
        echo "$label: ", implode(",", $out), "\n";
    }
}
$h = new H();
$h->run("t6a");
$h->run("t6b");
