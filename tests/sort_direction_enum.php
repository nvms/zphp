<?php
// php 8.6's SortDirection, a unit enum of the standard extension
var_dump(SortDirection::cases());
var_dump(SortDirection::Descending->name, SortDirection::Ascending === SortDirection::Ascending);
$r = new ReflectionEnum(SortDirection::class);
var_dump($r->isInternal(), $r->isFinal(), $r->isBacked(), $r->getExtensionName());
var_dump(SortDirection::Ascending instanceof UnitEnum, SortDirection::Ascending instanceof BackedEnum);
var_dump(method_exists(SortDirection::class, 'from'));
var_dump(in_array('SortDirection', (new ReflectionExtension('standard'))->getClassNames()));
// php declares its internal enums without final; a declared one is final
enum Mine { case A; }
foreach ([SortDirection::class, RoundingMode::class, Random\IntervalBoundary::class, PropertyHookType::class, Mine::class] as $c) {
    $r = new ReflectionClass($c);
    echo $c, " ", var_export($r->isFinal(), true), " ", $r->getModifiers(), "\n";
}
