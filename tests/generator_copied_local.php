<?php
// a generator copied into a second local keeps its own reference

class Held {
    function __destruct() {
        echo "held released\n";
    }
}

function gen($held) {
    yield 1;
    echo "resumed\n";
}
function copies() {
    $gen = gen(new Held);
    $copy = $gen;
    $gen = null;
    echo "copied\n";
    foreach ($copy as $v) {
        echo "value $v\n";
    }
    var_dump($copy->valid());
}
copies();
echo "done\n";
