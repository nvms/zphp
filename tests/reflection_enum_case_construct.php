<?php
enum Status: string { case Active = 'a'; case Inactive = 'i'; }
enum Plain { case Yes; case No; }

// direct construction of UnitCase
$u = new ReflectionEnumUnitCase(Plain::class, 'Yes');
echo $u->getName(), "\n";
echo $u->getValue()->name, "\n";

// direct construction of BackedCase
$b = new ReflectionEnumBackedCase(Status::class, 'Active');
echo $b->getName(), "\n";
echo $b->getBackingValue(), "\n";
echo $b->getValue()->value, "\n";

// with class names as strings
$u2 = new ReflectionEnumUnitCase('Plain', 'No');
echo $u2->getName(), "\n";
$b2 = new ReflectionEnumBackedCase('Status', 'Inactive');
echo $b2->getName(), "=", $b2->getBackingValue(), "\n";

// from ReflectionEnum::getCase
$re = new ReflectionEnum(Status::class);
$c = $re->getCase('Active');
echo $c->getName(), "\n";

// hasCase / getCases
var_dump($re->hasCase('Active'));
var_dump($re->hasCase('NotThere'));
foreach ($re->getCases() as $case) {
    echo $case->getName(), "\n";
}

// isBacked / getBackingType
var_dump($re->isBacked());
echo $re->getBackingType(), "\n";

$rp = new ReflectionEnum(Plain::class);
var_dump($rp->isBacked());

// ReflectionClass::isEnum
var_dump((new ReflectionClass(Status::class))->isEnum());
var_dump((new ReflectionClass(Plain::class))->isEnum());
var_dump((new ReflectionClass(stdClass::class))->isEnum());
