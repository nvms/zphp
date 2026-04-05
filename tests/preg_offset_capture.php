<?php

// PREG_OFFSET_CAPTURE with preg_match
preg_match('/(\w+)\s(\w+)/', 'hello world', $matches, PREG_OFFSET_CAPTURE);
echo $matches[0][0] . "\n";
echo $matches[0][1] . "\n";
echo $matches[1][0] . "\n";
echo $matches[1][1] . "\n";
echo $matches[2][0] . "\n";
echo $matches[2][1] . "\n";

// named groups interleaved
preg_match('/(?P<first>\w+)\s(?P<second>\w+)/', 'hello world', $m);
echo $m[0] . "\n";
echo $m['first'] . "\n";
echo $m[1] . "\n";
echo $m['second'] . "\n";
echo $m[2] . "\n";
