<?php
// __unserialize gets the serialized keys as written, mangled names and all;
// the date classes restore a private property only for a class that exists

class P {
    private $a = 1;
    protected $b = 2;
    public $c = 3;
    public function __unserialize(array $data): void {
        foreach ($data as $k => $v) echo str_replace("\0", "!", $k), " => ", $v, "\n";
    }
}
unserialize(str_replace("!", "\0", 'O:1:"P":4:{s:4:"!P!a";i:5;s:4:"!*!b";i:6;s:1:"c";i:7;s:4:"!Q!d";i:8;}'));

class I extends DateTimeImmutable {
    private $var1 = 1;
    private $var2 = 0;
    protected $var3 = 3;
}
foreach (['I', 'J'] as $owner) {
    $s = 'O:1:"I":6:{s:4:"date";s:26:"2023-03-09 17:03:11.123456";s:13:"timezone_type";i:3;s:8:"timezone";s:3:"UTC";s:' . (strlen($owner) + 6) . ':"!' . $owner . '!var2";i:2;s:7:"!*!var3";i:9;s:4:"var4";i:4;}';
    print_r(unserialize(str_replace("!", "\0", $s)));
}
