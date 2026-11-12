<?php
trait Shape {
    protected string $shape = 'square';
}
enum Suit {
    use Shape;
    case Hearts;
}
echo "unreachable\n";
