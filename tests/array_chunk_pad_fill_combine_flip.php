<?php
print_r(array_chunk([1,2,3,4,5,6,7], 3));
print_r(array_chunk([1,2,3,4,5,6,7], 3, true));
print_r(array_chunk(["a"=>1,"b"=>2,"c"=>3,"d"=>4], 2));
print_r(array_chunk(["a"=>1,"b"=>2,"c"=>3,"d"=>4], 2, true));
print_r(array_chunk([], 3));
print_r(array_chunk([1], 5));
print_r(array_chunk([1,2,3], 1));
print_r(array_chunk([1,2,3,4,5], 10, true));

print_r(array_pad([1,2,3], 5, 0));
print_r(array_pad([1,2,3], -5, 0));
print_r(array_pad([1,2,3], 3, 0));
print_r(array_pad([1,2,3], 2, 0));
print_r(array_pad([1,2,3], 0, 0));
print_r(array_pad([], 3, "x"));
print_r(array_pad([], -3, "x"));
print_r(array_pad(["a"=>1,"b"=>2], 4, 0));
print_r(array_pad(["a"=>1,"b"=>2], -4, 0));

print_r(array_fill_keys(["a","b","c"], 0));
print_r(array_fill_keys([1,2,3], "x"));
print_r(array_fill_keys([1, "1", 1.5, "a", true, false, null], "v"));
print_r(array_fill_keys([], "x"));

print_r(array_combine(["a","b","c"], [1,2,3]));
print_r(array_combine([], []));
print_r(array_combine([1,2,3], ["x","y","z"]));
try { array_combine(["a","b"], [1,2,3]); echo "no\n"; } catch (\ValueError $e) { echo "ve:", strlen($e->getMessage())>0?"y":"n", "\n"; }
try { array_combine(["a","b","c"], [1]); echo "no\n"; } catch (\ValueError $e) { echo "ve\n"; }

print_r(array_flip([1,2,3]));
print_r(array_flip(["a"=>1,"b"=>2,"c"=>3]));
print_r(array_flip(["a"=>"x","b"=>"y"]));
print_r(array_flip([]));
print_r(array_flip([1,1,2,2,3]));

$mixed = [0=>"a", "k"=>"b", 5=>"c"];
print_r(array_flip($mixed));

echo array_sum(array_chunk(range(1,100), 10)[0]), "\n";
echo array_sum(array_chunk(range(1,100), 10)[9]), "\n";

$big = array_pad([], 1000, 1);
echo count($big), " ", array_sum($big), "\n";
