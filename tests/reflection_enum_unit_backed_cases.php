<?php
enum Status {
    case Active;
    case Pending;
    case Closed;
}

$rc = new ReflectionEnum("Status");
echo $rc->getName(), "\n";
echo $rc->isEnum() ? "y" : "n", "\n";
echo $rc->isBacked() ? "y" : "n", "\n";

$cases = $rc->getCases();
foreach ($cases as $c) echo $c->getName(), " ";
echo "\n";

enum Priority: int {
    case Low = 1;
    case Medium = 5;
    case High = 10;
}

$rc = new ReflectionEnum("Priority");
echo $rc->isBacked() ? "y" : "n", "\n";
echo $rc->getBackingType()->getName(), "\n";

foreach ($rc->getCases() as $c) {
    echo $c->getName(), "=", $c->getValue()->value, "\n";
}

enum Color: string {
    case Red = "red";
    case Green = "green";
    case Blue = "blue";
}

$rc = new ReflectionEnum("Color");
echo $rc->getBackingType()->getName(), "\n";

foreach ($rc->getCases() as $c) {
    echo $c->getName(), "=", $c->getValue()->value, " ";
}
echo "\n";

$case = $rc->getCase("Red");
echo $case->getName(), " ", $case->getValue()->value, "\n";

echo $rc->hasCase("Red") ? "y" : "n", "\n";
echo $rc->hasCase("nope") ? "y" : "n", "\n";

interface Labelable {
    public function label(): string;
}

enum Weekday: int implements Labelable {
    case Mon = 1;
    case Tue = 2;
    case Wed = 3;
    case Thu = 4;
    case Fri = 5;
    case Sat = 6;
    case Sun = 7;
    public function label(): string {
        return $this->name;
    }
}

$rc = new ReflectionEnum("Weekday");
echo count($rc->getCases()), "\n";
echo $rc->implementsInterface("Labelable") ? "y" : "n", "\n";

$methods = $rc->getMethods();
$names = array_map(fn($m) => $m->getName(), $methods);
echo in_array("label", $names) ? "y" : "n", "\n";

enum HttpStatus: int {
    case Ok = 200;
    case NotFound = 404;
    case ServerError = 500;
    public const DEFAULT = self::Ok;
}

$rc = new ReflectionEnum("HttpStatus");
$consts = $rc->getConstants();
echo isset($consts["DEFAULT"]) ? "y" : "n", "\n";

$rc = new ReflectionEnum("Status");
echo $rc->isEnum() ? "y" : "n", "\n";

$c = new ReflectionEnumUnitCase(Status::class, "Active");
echo $c->getName(), "\n";

$c = new ReflectionEnumBackedCase(Priority::class, "Low");
echo $c->getName(), " ", $c->getValue()->value, "\n";

echo $c->getBackingValue() === 1 ? "y" : "n", "\n";

echo Status::Active === Status::cases()[0] ? "y" : "n", "\n";
echo Priority::Low->value, "\n";

$cls = new ReflectionClass("Status");
echo $cls->isEnum() ? "y" : "n", "\n";

$rc = new ReflectionEnum("Status");
echo $rc->getDocComment() === false ? "f" : strlen($rc->getDocComment()), "\n";

foreach ((new ReflectionEnum("Priority"))->getCases() as $c) {
    $instance = $c->getValue();
    echo $instance->name, "=", $instance->value, "\n";
}

$cases_arr = (new ReflectionEnum("Color"))->getCases();
echo count($cases_arr), "\n";
echo $cases_arr[1]->getName(), "\n";

class Demo {
    public function show(): string { return "demo"; }
}

$rc = new ReflectionClass("Demo");
echo $rc->isEnum() ? "y" : "n", "\n";

enum Type: string {
    case A = "alpha";
    case B = "beta";
    public function describe(): string {
        return "I am " . $this->name;
    }
}

$rc = new ReflectionEnum("Type");
$method = $rc->getMethod("describe");
echo $method->getName(), "\n";
echo $method->invoke(Type::A), "\n";

$values = [];
foreach ($rc->getCases() as $c) {
    $values[] = $c->getName() . ":" . $c->getValue()->value;
}
print_r($values);

$rc = new ReflectionEnum("Color");
$ifaces = $rc->getInterfaceNames();
$found_unit = false;
$found_backed = false;
foreach ($ifaces as $i) {
    if (str_ends_with($i, "UnitEnum")) $found_unit = true;
    if (str_ends_with($i, "BackedEnum")) $found_backed = true;
}
echo $found_unit ? "y" : "n", "\n";
echo $found_backed ? "y" : "n", "\n";

$rc = new ReflectionEnum("Status");
echo $rc->isBacked() ? "y" : "n", "\n";
