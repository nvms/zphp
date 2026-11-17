<?php
// ReflectionEnumUnitCase::getEnum() reflects the case's enum
enum Suit {
    case Hearts;
    case Spades;
}
enum Size: int {
    case Small = 1;
    case Large = 2;
}
$unit = new ReflectionEnumUnitCase(Suit::class, 'Spades');
$enum = $unit->getEnum();
var_dump(get_class($enum), $enum->getName(), $enum->isBacked(), count($enum->getCases()));
$backed = new ReflectionEnumBackedCase(Size::class, 'Large');
$enum = $backed->getEnum();
var_dump(get_class($enum), $enum->getName(), $enum->isBacked(), (string) $enum->getBackingType());
var_dump($enum->getCase('Small')->getBackingValue());
echo (new ReflectionMethod('ReflectionEnumUnitCase', 'getEnum'));
