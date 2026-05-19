<?php
// regression: SplStack iteration keys match PHP - the key is the
// underlying array index of the current item (starts at len-1 for the top
// and decreases toward 0 as the cursor moves down). previously zphp
// returned 'distance from top' which inverted to 0,1,2 instead of 2,1,0
$s = new SplStack();
$s->push("a"); $s->push("b"); $s->push("c");
foreach ($s as $k => $v) echo "$k=$v\n";   // 2=c 1=b 0=a

// after pop, iteration adjusts
$s->pop();
echo "---\n";
foreach ($s as $k => $v) echo "$k=$v\n";   // 1=b 0=a
