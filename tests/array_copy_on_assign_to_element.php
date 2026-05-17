<?php
// regression: assigning an array into another array element (or chained via
// property) must clone the source so the destination has an independent
// iterator pointer. before the array_set_local/array_set_chain/prop_set_chain
// clone-on-value-assign fix, both copies advanced together which broke any
// code that re-reads its priority/iteration source after a do-while loop
// (e.g. WordPress's WP_Hook::apply_filters).
class H {
    public array $priorities = [];
    public array $iterations = [];
}
$h = new H();
$h->priorities = [10, 20];
$h->iterations[0] = $h->priorities;
do {
    echo "1st: ", current($h->iterations[0]), "\n";
} while (false !== next($h->iterations[0]));
$h->iterations[1] = $h->priorities;
do {
    echo "2nd: ", current($h->iterations[1]), "\n";
} while (false !== next($h->iterations[1]));

// also check plain array-into-array
$container = [];
$container[0] = $h->priorities;
next($container[0]);
echo "src current: ", current($h->priorities), "\n";
echo "dst current: ", current($container[0]), "\n";

// and via property-chain access
$h->iterations[2] = $h->priorities;
next($h->iterations[2]);
echo "src after: ", current($h->priorities), "\n";
echo "iter2 after: ", current($h->iterations[2]), "\n";
