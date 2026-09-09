<?php
// string-heavy loop that must run at a flat memory footprint: every kind of
// transient string a request produces (concat, formatting, natives, json,
// serialize, casts, dynamic keys and properties, __toString) is created and
// dropped each round. tests/memory_soak samples RSS while this runs
class P
{
    public $v;
    public function __toString(): string
    {
        return "p:" . $this->v;
    }
}

$rounds = (int) ($argv[1] ?? 300000);
$obj = new stdClass();
$acc = 0;
for ($i = 0; $i < $rounds; $i++) {
    $s = "item-" . $i . "-" . ($i * 3);
    $t = sprintf("%s|%05d|%.2f", $s, $i % 1000, $i / 7);
    $u = str_replace("item", "it", strtoupper($t));
    $parts = explode("|", $u);
    $j = implode(",", $parts);
    $k = substr($j, 2, 10) . trim("  " . $s . "  ");
    $m = preg_replace('/\d+/', '#', $k);
    $n = json_encode(["a" => $m, "b" => [$i, $s]]);
    $d = json_decode($n, true);
    $arr = ["k$i" => $d["a"], "x" => str_pad((string) $i, 8, "0", STR_PAD_LEFT)];
    $obj->{"p" . ($i % 50)} = $arr["x"];
    $p = new P();
    $p->v = $i;
    $q = "<" . $p . ">" . strlen($p) . (string) ($i * 2);
    $ser = unserialize(serialize([$q, $arr]));
    $acc += strlen($ser[0]) + count($d["b"]) + strlen(number_format($i * 1.5, 2));
}
echo "done ", $acc, "\n";
