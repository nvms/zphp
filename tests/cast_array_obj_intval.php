<?php
// (int) casts
var_dump((int)"abc");
var_dump((int)"123abc");
var_dump((int)"abc123");
var_dump((int)"1.5");
var_dump((int)"1.5e3");
var_dump((int)"   42");
var_dump((int)"+42");
var_dump((int)"-42");
var_dump((int)"0x10"); // 0 in cast
var_dump((int)"010"); // 10 in cast
var_dump((int)"");
var_dump((int)null);
var_dump((int)true);
var_dump((int)false);
var_dump((int)1.9);
var_dump((int)-1.9);
// PHP and zphp differ on float-to-int overflow specifics (architectural)

// (float) casts
var_dump((float)"abc");
var_dump((float)"1.5");
var_dump((float)"1.5e3");
var_dump((float)"1.2.3"); // 1.2
var_dump((float)".5");
var_dump((float)"abc.def");
var_dump((float)null);
var_dump((float)true);
var_dump((float)false);
var_dump((float)1);

// (string) casts
var_dump((string)1.5);
var_dump((string)0.0);
var_dump((string)-0.0); // -0
var_dump((string)true);
var_dump((string)false);
var_dump((string)null);
var_dump((string)100);

// (bool) casts
var_dump((bool)"");
var_dump((bool)"0");
var_dump((bool)"false"); // true (non-empty)
var_dump((bool)"00"); // true
var_dump((bool)0);
var_dump((bool)1);
var_dump((bool)0.0);
var_dump((bool)0.1);
var_dump((bool)null);
var_dump((bool)[]);
var_dump((bool)[0]);

// (array) of object
class P {
    public int $a = 1;
    private string $b = "priv";
    protected array $c = [1, 2];
}
$arr = (array)(new P);
foreach ($arr as $k => $v) {
    echo "[" . bin2hex($k) . "]=" . (is_array($v) ? "arr(" . count($v) . ")" : $v), "|";
}
echo "\n";

// settype
$v = "123";
settype($v, "int");
var_dump($v);

$v = "1.5";
settype($v, "float");
var_dump($v);

$v = 1;
settype($v, "string");
var_dump($v);

$v = "1";
settype($v, "bool");
var_dump($v);

$v = ["a" => 1];
settype($v, "array");
var_dump($v); // unchanged

$v = "hello";
settype($v, "array");
print_r($v);

// intval with base
var_dump(intval("ff", 16));
var_dump(intval("0xff", 16));
var_dump(intval("0x10", 0)); // 16 (0x prefix detected)
var_dump(intval("010", 0)); // 8 (0 prefix detected)
var_dump(intval("0b101", 0)); // 5
var_dump(intval("100", 10));
var_dump(intval("100", 2)); // 4
var_dump(intval(""));
var_dump(intval("abc"));
var_dump(intval("123abc"));

// floatval
var_dump(floatval("1.5"));
var_dump(floatval("abc"));
var_dump(floatval("1.5abc"));
var_dump(floatval("1e3"));
var_dump(floatval(""));

// boolval
var_dump(boolval(""));
var_dump(boolval("0"));
var_dump(boolval("a"));
var_dump(boolval(0));
var_dump(boolval(1));
var_dump(boolval([]));

// strval
echo strval(true), "|"; // "1"
echo strval(false), "|"; // ""
echo strval(null), "|"; // ""
echo strval(1.5), "|";
echo strval(-1.5), "|";
echo strval(100), "\n";
