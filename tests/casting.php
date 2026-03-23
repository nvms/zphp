<?php

echo (int)"42";
echo "\n";

echo (int)3.9;
echo "\n";

echo (int)true;
echo "\n";

echo (int)false;
echo "\n";

echo (float)"3.14";
echo "\n";

echo (float)42;
echo "\n";

echo (string)42;
echo "\n";

echo (string)3.14;
echo "\n";

echo (string)true;
echo "\n";

echo (string)false;
echo "\n";

echo (string)null;
echo "\n";

echo (bool)"hello" ? 'true' : 'false';
echo "\n";

echo (bool)"" ? 'true' : 'false';
echo "\n";

echo (bool)0 ? 'true' : 'false';
echo "\n";

echo (bool)1 ? 'true' : 'false';
echo "\n";

$a = (array)42;
echo count($a);
echo "\n";
echo $a[0];
echo "\n";

$b = (array)"hello";
echo $b[0];
echo "\n";
