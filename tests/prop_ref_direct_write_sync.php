<?php

// `$r = &$obj->prop` makes $r and $obj->prop ONE storage in PHP. writing the
// property DIRECTLY (not through $r) must be visible through $r, in BOTH
// directions and through every write form (plain =, compound, ++/--, dynamic
// name, static props). zphp keeps the prop slot and the ref cell as two views
// and must sync them on every prop write (the reverse of cell->prop sync).

class Holder
{
    public int $n = 1;
    public string $s = 'a';
    public array $arr = [];
    public static int $st = 10;
}

$h = new Holder();

// plain assignment after bind
$r = &$h->n;
$h->n = 42;
echo "plain =: ", $r, "\n";              // 42

// compound + inc/dec
$h->n += 8;
echo "+=: ", $r, "\n";                   // 50
$h->n++;
echo "++: ", $r, "\n";                   // 51
--$h->n;
echo "--: ", $r, "\n";                   // 50

// reverse direction: writing through $r reaches the property
$r = 999;
echo "reverse: ", $h->n, "\n";           // 999

// string property + concat-assign
$rs = &$h->s;
$h->s = 'x';
echo "str =: ", $rs, "\n";               // x
$h->s .= 'y';
echo "str .=: ", $rs, "\n";              // xy

// dynamic property name
$rn = &$h->n;
$prop = 'n';
$h->$prop = 7;
echo "dyn name: ", $rn, "\n";            // 7

// static property reference
$rst = &Holder::$st;
Holder::$st = 77;
echo "static =: ", $rst, "\n";           // 77
Holder::$st += 3;
echo "static +=: ", $rst, "\n";          // 80

// a fresh object with no ref bindings is unaffected (the guard path)
$h2 = new Holder();
$h2->n = 5;
echo "unbound obj: ", $h2->n, "\n";      // 5

// two references to two different props don't cross-talk
$a = new Holder();
$ra = &$a->n;
$rb = &$a->s;
$a->n = 100;
$a->s = 'zz';
echo "two refs: ", $ra, " ", $rb, "\n";  // 100 zz
