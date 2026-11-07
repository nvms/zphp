<?php
// an enum may not declare the methods php gives it
echo "not reached\n";
enum Suit: string {
    case Hearts = 'H';
    public static function tryFrom(string $value): ?static { return null; }
}
