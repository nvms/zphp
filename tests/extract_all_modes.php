<?php
$z = 100;
extract(["z" => 200], EXTR_SKIP);
echo $z, "\n";

$z = 100;
extract(["z" => 200], EXTR_OVERWRITE);
echo $z, "\n";

extract(["a" => 1, "b" => 2], EXTR_PREFIX_ALL, "p");
echo $p_a, " ", $p_b, "\n";

extract(["valid" => 1, "1bad" => 2], EXTR_PREFIX_INVALID, "p");
echo $valid, " ", $p_1bad, "\n";

$same = 5;
extract(["same" => 10, "diff" => 20], EXTR_PREFIX_SAME, "p");
echo $same, " ", $p_same, " ", $diff, "\n";

$exists = 1;
extract(["exists" => 100, "new" => 2], EXTR_IF_EXISTS);
echo $exists, " ", isset($new) ? $new : "ne", "\n";

extract(["fresh" => 99], EXTR_PREFIX_IF_EXISTS, "p");
echo "fresh=", $fresh ?? "ne", " p_fresh=", $p_fresh ?? "ne", "\n";

$existsB = 1;
extract(["existsB" => 100, "newB" => 2], EXTR_PREFIX_IF_EXISTS, "p");
echo "existsB=$existsB p_existsB=", $p_existsB ?? "ne", " newB=", $newB ?? "ne", "\n";

$count = extract(["x" => 10, "y" => 20]);
echo "$count $x $y\n";
