<?php
// alternative control structure syntax (colon form)

// foreach
$items = [10, 20, 30];
foreach ($items as $item):
    echo $item . " ";
endforeach;
echo "\n";

// foreach with key => value
$map = ['a' => 1, 'b' => 2, 'c' => 3];
foreach ($map as $k => $v):
    echo "$k=$v ";
endforeach;
echo "\n";

// if/elseif/else
$x = 2;
if ($x === 1):
    echo "one";
elseif ($x === 2):
    echo "two";
else:
    echo "other";
endif;
echo "\n";

// simple if (no else)
if (true):
    echo "yes";
endif;
echo "\n";

// while
$i = 0;
while ($i < 3):
    echo $i;
    $i++;
endwhile;
echo "\n";

// for
for ($j = 0; $j < 4; $j++):
    echo $j;
endfor;
echo "\n";

// nested alt syntax
$grid = [[1, 2], [3, 4]];
foreach ($grid as $row):
    foreach ($row as $cell):
        echo $cell . " ";
    endforeach;
endforeach;
echo "\n";

// alt if inside alt foreach
$vals = [1, 2, 3, 4, 5];
foreach ($vals as $v):
    if ($v % 2 === 0):
        echo "e";
    else:
        echo "o";
    endif;
endforeach;
echo "\n";
