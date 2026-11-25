<?php
// php 8.6 lets an enum declare __debugInfo, which var_dump, print_r and
// debug_zval_dump then show
enum Suit: string {
    case Hearts = 'H';
    case Spades = 'S';
    public function __debugInfo(): array {
        return ['label' => strtolower($this->name), 'value' => $this->value];
    }
}
enum Plain { case A; }
var_dump(Suit::Hearts);
var_dump([Suit::Spades, Plain::A]);
print_r(Suit::Hearts);
echo "\n";
print_r(Plain::A);
echo "\n";
var_export(Suit::Hearts);
echo "\n";
debug_zval_dump(Suit::Hearts);
var_dump((new ReflectionEnum(Suit::class))->hasMethod('__debugInfo'));
