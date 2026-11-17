<?php
// an interface extending two interfaces that declare the same method checks
// the one it inherits first against the other (the diamond and the
// compatible pair declare without errors; the later, richer get() is
// incompatible with the first one inherited)

interface Base { function shared(int $x); }
interface Left extends Base { function left(); }
interface Right extends Base { function right(); }
interface Both extends Left, Right {}

interface Wide { function m(int $x); }
interface Narrow { function m(int $x, $y = null); }
interface Ok extends Narrow, Wide {}

interface PsrLike { function get(string $id); }
interface Richer extends PsrLike { function get(string $id, int $behavior = 1): ?object; }
interface Tagged extends Richer {}
interface BothOrders extends Richer, PsrLike {}
interface OtherOrder extends PsrLike, Richer {}
