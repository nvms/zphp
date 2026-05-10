<?php
print_r(array_diff([1,2,3,4,5], [2,4]));
print_r(array_diff([1,2,3], []));
print_r(array_diff([], [1,2,3]));
print_r(array_diff([1,2,3,4], [2,4], [3]));
print_r(array_diff(["a"=>1,"b"=>2,"c"=>3], [2]));
print_r(array_diff([1,2,3], [1,2,3]));
print_r(array_diff(["x","y","z"], ["X","Y"]));

print_r(array_diff_key(["a"=>1,"b"=>2,"c"=>3], ["a"=>0,"c"=>0]));
print_r(array_diff_key(["a"=>1,"b"=>2,"c"=>3], ["a"=>0]));
print_r(array_diff_key(["a"=>1,"b"=>2], []));
print_r(array_diff_key([], ["a"=>1]));
print_r(array_diff_key([1,2,3,4], [10=>"x", 1=>"y"]));
print_r(array_diff_key(["a"=>1,"b"=>2,"c"=>3], ["a"=>5,"b"=>9]));

print_r(array_diff_assoc(["a"=>1,"b"=>2,"c"=>3], ["a"=>1,"b"=>9]));
print_r(array_diff_assoc(["a"=>1,"b"=>2], ["a"=>1,"b"=>2]));
print_r(array_diff_assoc(["a"=>"x","b"=>"y"], ["a"=>"x","c"=>"z"]));
print_r(array_diff_assoc([1,2,3,4], [1,2,3]));
print_r(array_diff_assoc(["k"=>1], ["k"=>"1"]));

print_r(array_intersect([1,2,3,4,5], [2,4,6]));
print_r(array_intersect([1,2,3], []));
print_r(array_intersect(["a"=>1,"b"=>2,"c"=>3], [1,3]));
print_r(array_intersect([1,2,3,4], [2,3], [3,4]));
print_r(array_intersect([1,2,3], [1,2,3]));

print_r(array_intersect_key(["a"=>1,"b"=>2,"c"=>3], ["a"=>0,"c"=>0]));
print_r(array_intersect_key(["a"=>1,"b"=>2], ["c"=>0]));
print_r(array_intersect_key([], ["a"=>1]));
print_r(array_intersect_key(["a"=>1,"b"=>2,"c"=>3], ["a"=>0,"d"=>0], ["a"=>0]));

print_r(array_intersect_assoc(["a"=>1,"b"=>2,"c"=>3], ["a"=>1,"b"=>9,"c"=>3]));
print_r(array_intersect_assoc(["a"=>1,"b"=>2], ["a"=>"1"]));

print_r(array_udiff([1,2,3,4,5], [2,4], fn($a,$b) => $a - $b));
print_r(array_udiff(
    [(object)["v"=>1], (object)["v"=>2], (object)["v"=>3]],
    [(object)["v"=>2]],
    fn($a,$b) => $a->v - $b->v
));
print_r(array_udiff([1,2,3], [1,2,3], fn($a,$b) => $a - $b));
print_r(array_udiff([10,20,30], [], fn($a,$b) => $a - $b));

print_r(array_uintersect([1,2,3,4,5], [2,4,6], fn($a,$b) => $a - $b));
print_r(array_uintersect(
    [(object)["v"=>1], (object)["v"=>2]],
    [(object)["v"=>2], (object)["v"=>3]],
    fn($a,$b) => $a->v - $b->v
));
print_r(array_uintersect([1,2,3], [4,5,6], fn($a,$b) => $a - $b));

print_r(array_diff_ukey(["a"=>1,"b"=>2,"c"=>3], ["a"=>0,"c"=>0], fn($a,$b) => strcmp($a,$b)));
print_r(array_diff_ukey(["abc"=>1,"def"=>2], ["ABC"=>0], fn($a,$b) => strcasecmp($a,$b)));

print_r(array_intersect_ukey(["a"=>1,"b"=>2,"c"=>3], ["a"=>0,"c"=>0], fn($a,$b) => strcmp($a,$b)));
print_r(array_intersect_ukey(["abc"=>1,"def"=>2], ["ABC"=>0], fn($a,$b) => strcasecmp($a,$b)));

print_r(array_udiff_assoc(
    ["a"=>1,"b"=>2,"c"=>3],
    ["a"=>1,"b"=>9],
    fn($x,$y) => $x - $y
));

print_r(array_uintersect_assoc(
    ["a"=>1,"b"=>2,"c"=>3],
    ["a"=>1,"b"=>2,"d"=>4],
    fn($x,$y) => $x - $y
));

print_r(array_udiff_uassoc(
    ["a"=>1,"b"=>2,"c"=>3],
    ["A"=>1,"b"=>9],
    fn($x,$y) => $x - $y,
    fn($a,$b) => strcasecmp($a,$b)
));

print_r(array_uintersect_uassoc(
    ["a"=>1,"b"=>2,"c"=>3],
    ["A"=>1,"B"=>9,"c"=>3],
    fn($x,$y) => $x - $y,
    fn($a,$b) => strcasecmp($a,$b)
));

print_r(array_diff_assoc(
    ["a"=>1,"b"=>2,"c"=>3],
    ["a"=>1,"b"=>9],
    ["c"=>3]
));

print_r(array_intersect_key([], []));
print_r(array_diff_key([], []));
print_r(array_intersect([], []));
print_r(array_diff([], []));
