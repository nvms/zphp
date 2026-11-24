<?php
// an invalid key stops json_encode at once, so later values are never
// visited and their errors don't replace the key's; with partial output the
// key becomes "" and encoding goes on
class Later implements JsonSerializable {
    public function jsonSerialize(): mixed {
        echo "jsonSerialize() called\n";
        return 1;
    }
}

function show($value, $flags = 0) {
    var_dump(json_encode($value, $flags));
    var_dump(json_last_error(), json_last_error_msg());
}

echo "array:\n";
show(["\xff" => 1, 'next' => new Later()]);
echo "array, later NAN:\n";
show(["\xff" => 1, 'next' => NAN]);
echo "nested:\n";
show(['a' => ['b' => ["\xfe" => 1]], 'c' => new Later()]);

echo "dynamic property:\n";
$o = new stdClass();
$o->{"\xff"} = 1;
$o->next = new Later();
show($o);

echo "declared property after a materialized table:\n";
class Holder {
    public $x = 1;
}
$h = new Holder();
$h->{"bad\xff"} = 2;
$h->later = new Later();
show($h);

echo "partial output:\n";
show(["\xff" => 1, 'next' => new Later(), 'nan' => NAN], JSON_PARTIAL_OUTPUT_ON_ERROR);
show($o, JSON_PARTIAL_OUTPUT_ON_ERROR);

echo "substitute:\n";
show(["\xff" => 1], JSON_INVALID_UTF8_SUBSTITUTE);

echo "the same arrays encode again afterwards:\n";
$a = ['k' => [1, 2]];
$bad = ["\xff" => $a, 'k' => $a];
show($bad);
show($a);
