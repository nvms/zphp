<?php
// yield followed by a token no expression starts with is a bare yield, so
// `yield * -1` multiplies the value the yield receives

function gen() {
    var_dump(yield +1);
    var_dump(yield -1);
    var_dump(yield * -1);
    var_dump((yield) . "!");
}

for ($gen = gen(); $gen->valid(); $gen->send(1)) {
    var_dump($gen->current());
}
