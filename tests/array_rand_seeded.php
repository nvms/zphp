<?php
// array_rand draws from the engine mt_srand seeds, as php_array_pick_keys
// does: picks repeat for a seed, and the draw advances mt_rand's sequence
$list = range(10, 29);
$map = ['a' => 1, 'b' => 2, 'c' => 3, 'd' => 4, 'e' => 5, 'f' => 6, 'g' => 7];
foreach ([0, 1, 42, 12345] as $seed) {
    mt_srand($seed);
    echo "seed $seed: ", array_rand($list), ' ', array_rand($map), ' ',
        json_encode(array_rand($list, 3)), ' ', json_encode(array_rand($map, 5)), ' ',
        json_encode(array_rand($list, 19)), ' ', mt_rand(), "\n";
}
mt_srand(7);
$a = array_rand($list, 4);
mt_srand(7);
var_dump($a === array_rand($list, 4));
var_dump(array_rand(['only' => 1]), array_rand([5 => 'x'], 1));
