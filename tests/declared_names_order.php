<?php
// get_declared_classes/interfaces/traits list the class table in the order
// names were added; classes leave out interfaces and traits, and an alias is
// listed under its lowercased name
class Zeta {}
interface Beta {}
trait Gamma {}
abstract class Alpha {}
class_alias('Zeta', 'ZetaAlias');
class_alias('Gamma', 'GammaAlias');
class_alias('Beta', 'BetaAlias');
final class Epsilon {}

function tail(array $names, array $mine) {
    return array_values(array_filter($names, fn($n) => in_array($n, $mine, true)));
}
$mine = ['Zeta', 'Beta', 'Gamma', 'Alpha', 'zetaalias', 'gammaalias', 'betaalias', 'Epsilon'];
var_dump(tail(get_declared_classes(), $mine));
var_dump(tail(get_declared_interfaces(), $mine));
var_dump(tail(get_declared_traits(), $mine));
var_dump(in_array('Traversable', get_declared_classes(), true), in_array('Traversable', get_declared_interfaces(), true));
