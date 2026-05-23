<?php
// bitwise OR / AND / XOR in attribute arg expressions involving user-defined
// constants. previously zphp folded only when both sides were Attribute::*
// well-known flags; user-defined constants now defer to attribute load time.
const FLAG_A = 1;
const FLAG_B = 2;
const FLAG_C = 4;

#[Attribute(Attribute::TARGET_CLASS | Attribute::TARGET_METHOD)]
class MyAttr
{
    public function __construct(public int $flags) {}
}

#[MyAttr(FLAG_A | FLAG_B | FLAG_C)]
class TOr {}

#[MyAttr(FLAG_A & FLAG_B)]
class TAnd {}

#[MyAttr(FLAG_A ^ FLAG_C)]
class TXor {}

#[MyAttr(FLAG_A | Attribute::TARGET_METHOD)]
class TMixed {}

#[MyAttr(FLAG_A | FLAG_B | Attribute::TARGET_METHOD)]
class TTripleMixed {}

foreach (['TOr', 'TAnd', 'TXor', 'TMixed', 'TTripleMixed'] as $cls) {
    $attrs = (new ReflectionClass($cls))->getAttributes();
    foreach ($attrs as $a) {
        $inst = $a->newInstance();
        echo $cls, ": ", $inst->flags, "\n";
    }
}
