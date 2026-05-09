<?php
date_default_timezone_set('UTC');
// DateInterval from string format
$i = new DateInterval('P1Y2M3DT4H5M6S');
echo "$i->y/$i->m/$i->d $i->h:$i->i:$i->s\n";
$i = new DateInterval('P1Y');
echo "$i->y/$i->m/$i->d\n";
$i = new DateInterval('PT30M');
echo "$i->h:$i->i\n";
$i = new DateInterval('P1W');
echo "days=$i->d\n"; // 7
$i = new DateInterval('P10D');
echo $i->format('%d'), "\n";
$i = new DateInterval('P1Y2M3D');
echo $i->format('%y years %m months %d days'), "\n";
echo $i->format('%R%y'), "\n";

// DateTime arithmetic over month boundaries
$d = new DateTime('2024-01-31');
$d->modify('+1 month');
echo $d->format('Y-m-d'), "\n"; // March 02 - month overflow
$d = new DateTime('2024-03-31');
$d->modify('+1 month');
echo $d->format('Y-m-d'), "\n"; // May 01
$d = new DateTime('2024-01-15');
$d->add(new DateInterval('P1M'));
echo $d->format('Y-m-d'), "\n";
$d = new DateTime('2020-02-29');
$d->add(new DateInterval('P1Y'));
echo $d->format('Y-m-d'), "\n"; // 2021-03-01 (leap to non-leap)
$d = new DateTime('2024-02-29');
$d->add(new DateInterval('P4Y'));
echo $d->format('Y-m-d'), "\n"; // 2028-02-29
$d = new DateTime('2024-12-31');
$d->add(new DateInterval('P1D'));
echo $d->format('Y-m-d'), "\n";

// negative intervals
$i = new DateInterval('P1Y');
$i->invert = 1;
$d = new DateTime('2024-06-15');
$d->add($i);
echo $d->format('Y-m-d'), "\n"; // 2023-06-15

// diff over month boundaries
$d1 = new DateTime('2024-01-15');
$d2 = new DateTime('2024-03-10');
$di = $d1->diff($d2);
echo "$di->y $di->m $di->d days=$di->days\n";

// negative diff
$di = $d2->diff($d1);
echo "$di->y $di->m $di->d days=$di->days invert=$di->invert\n";

// str_replace with count
$count = 0;
echo str_replace("a", "X", "aaabbb", $count), " count=$count\n";
$count = 0;
echo str_replace(["a", "b"], "X", "aaabbb", $count), " count=$count\n";
$count = 0;
$res = str_replace(["a", "b"], ["X", "Y"], "aaabbb", $count);
echo "$res count=$count\n";
$count = 0;
$res = str_replace(["a", "b"], ["X"], "aaabbb", $count);
echo "$res count=$count\n"; // unmatched: replacement falls back to ""

// preg_split DELIM_CAPTURE
print_r(preg_split('/(\d+)/', 'abc123def456', -1, PREG_SPLIT_DELIM_CAPTURE));
print_r(preg_split('/(\W+)/', 'a, b. c', -1, PREG_SPLIT_DELIM_CAPTURE));
print_r(preg_split('/[\s,]+/', 'a,b c, d', -1, PREG_SPLIT_NO_EMPTY));
print_r(preg_split('/(\W+)/', 'a, b. c', 2, PREG_SPLIT_DELIM_CAPTURE));

// preg_grep
print_r(preg_grep('/^a/', ['apple', 'banana', 'avocado', 'cherry']));
print_r(preg_grep('/^a/', ['apple', 'banana', 'avocado', 'cherry'], PREG_GREP_INVERT));
print_r(preg_grep('/\d+/', ['x1', 'y2', 'z']));
