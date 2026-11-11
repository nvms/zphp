<?php
// a malformed string reports the offset php's scanner stops at: the length
// when it runs past the input, else the closing quote or semicolon

foreach ([
    's:1:"Europe/Kyiv";',
    's:5:"abc";',
    's:50:"abc";',
    's:3:"abc"x',
    's:3:"abc',
    'a:1:{i:0;s:2:"abc";}',
    'O:8:"stdClass":1:{s:1:"a";s:1:"Europe/Kyiv";}',
    'O:8:"DateTime":3:{s:4:"date";s:26:"2023-01-13 14:48:01.705516";s:13:"timezone_type";i:3;s:8:"timezone";s:1:"Europe/Kyiv";}',
] as $s) {
    var_dump(unserialize($s));
}
