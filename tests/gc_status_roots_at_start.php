<?php
// the root buffer is empty when the script starts; a reference cycle let go
// of is one possible root, which a collection frees

function show(string $label): void
{
    $s = gc_status();
    echo $label, ": runs=", $s['runs'], " collected=", $s['collected'], " roots=", $s['roots'], "\n";
}

show("start");
$a = [];
$a[] =& $a;
show("cycle made");
unset($a);
show("cycle dropped");
gc_collect_cycles();
gc_collect_cycles();
show("collected");
