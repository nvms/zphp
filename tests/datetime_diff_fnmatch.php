<?php
date_default_timezone_set('UTC');

// across midnight - was buggy: zphp said 1d 2h 30m, should be 0d 2h 30m
$c = new DateTime('2024-01-01 23:00:00');
$d = new DateTime('2024-01-02 01:30:00');
$cd = $c->diff($d);
echo "$cd->d d $cd->h h $cd->i m\n";

// just under one day
$e = new DateTime('2024-01-01 00:00:00');
$f = new DateTime('2024-01-01 23:59:59');
$ef = $e->diff($f);
echo "$ef->d d $ef->h h $ef->i m $ef->s s\n";

// exactly one day
$g = new DateTime('2024-01-01 00:00:00');
$h = new DateTime('2024-01-02 00:00:00');
$gh = $g->diff($h);
echo "$gh->d d $gh->h h\n";

// hours/minutes/seconds borrowing
$a = new DateTime('2024-01-01 10:30:45');
$b = new DateTime('2024-01-01 09:15:30');
$ab = $a->diff($b);
echo "rev: $ab->h h $ab->i m $ab->s s invert=$ab->invert\n";

// year diff
$y1 = new DateTime('2020-01-01 00:00:00');
$y2 = new DateTime('2024-06-15 00:00:00');
$y12 = $y1->diff($y2);
echo "$y12->y y $y12->m m $y12->d d\n";

// month borrowing across year boundary
$m1 = new DateTime('2023-12-31 00:00:00');
$m2 = new DateTime('2024-01-01 00:00:00');
$m12 = $m1->diff($m2);
echo "year: $m12->y y $m12->m m $m12->d d\n";

// DateInterval format
echo $y12->format('%y-%m-%d %h:%i:%s'), "\n";

// fnmatch
var_dump(fnmatch("*.txt", "test.txt"));
var_dump(fnmatch("*.txt", "test.php"));
var_dump(fnmatch("?at", "cat"));
var_dump(fnmatch("?at", "chat"));
var_dump(fnmatch("[abc]bc", "abc"));
var_dump(fnmatch("[abc]bc", "dbc"));
var_dump(fnmatch("*.t?t", "test.txt"));
var_dump(fnmatch("hello", "hello"));
var_dump(fnmatch("", ""));
