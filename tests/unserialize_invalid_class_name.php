<?php
// a class name no class could have fails at the object's start, before any
// lookup; a well formed unknown name gives an incomplete class

foreach ([
    'O:4:"D' . "\x06" . 'te":0:{}',
    'a:2:{i:0;i:1;i:1;O:3:"a b":0:{}}',
    'O:4:"\\Foo":0:{}',
    'O:1:"' . "\0" . '":0:{}',
    'O:0:"":0:{}',
    'O:7:"Unknown":0:{}',
    'O:9:"Ns\\Klass":0:{}',
    'O:4:"' . "\xc3\xa9t\xc3\xa9" . '":0:{}',
] as $s) {
    var_dump(@unserialize($s));
    echo error_get_last()["message"] ?? "", "\n";
    error_clear_last();
}
