<?php

class Animal {
    public string $name;
    public function __construct(string $name, int $age = 0) {
        $this->name = $name;
    }
    public function speak(): string { return "..."; }
    protected function breathe(): void {}
}

class Dog extends Animal {
    public function speak(): string { return "woof"; }
    public function fetch(string $item): string { return "fetched $item"; }
    public static function species(): string { return "Canis lupus"; }
}

interface Loggable {
    public function log(): string;
}

class Logger implements Loggable {
    public function log(): string { return "logged"; }
}

// ReflectionClass basics
$rc = new ReflectionClass('Dog');
echo $rc->getName() . "\n";
echo ($rc->getParentClass()->getName()) . "\n";
echo $rc->isInstantiable() ? "yes" : "no";
echo "\n";
echo $rc->isAbstract() ? "yes" : "no";
echo "\n";
echo $rc->isInterface() ? "yes" : "no";
echo "\n";

// constructor introspection
$ctor = $rc->getConstructor();
echo $ctor->getName() . "\n";
echo $ctor->getDeclaringClass()->getName() . "\n";
echo $ctor->isConstructor() ? "yes" : "no";
echo "\n";
echo $ctor->isPublic() ? "yes" : "no";
echo "\n";

// parameter introspection
$params = $ctor->getParameters();
echo count($params) . "\n";
echo $params[0]->getName() . "\n";
echo $params[0]->getType()->getName() . "\n";
echo $params[0]->getType()->isBuiltin() ? "builtin" : "class";
echo "\n";
echo $params[0]->getPosition() . "\n";
echo $params[0]->hasType() ? "yes" : "no";
echo "\n";
echo $params[0]->isOptional() ? "yes" : "no";
echo "\n";
echo $params[1]->getName() . "\n";
echo $params[1]->isDefaultValueAvailable() ? "yes" : "no";
echo "\n";
echo $params[1]->getDefaultValue() . "\n";
echo $params[1]->isOptional() ? "yes" : "no";
echo "\n";

// hasMethod
echo $rc->hasMethod('speak') ? "yes" : "no";
echo "\n";
echo $rc->hasMethod('fly') ? "yes" : "no";
echo "\n";
echo $rc->hasMethod('breathe') ? "yes" : "no";
echo "\n";

// getMethod
$speak = $rc->getMethod('speak');
echo $speak->getName() . "\n";
echo $speak->isPublic() ? "yes" : "no";
echo "\n";
echo $speak->isStatic() ? "yes" : "no";
echo "\n";

// static method
$species = $rc->getMethod('species');
echo $species->isStatic() ? "yes" : "no";
echo "\n";

// getMethods count
$methods = $rc->getMethods();
echo count($methods) . "\n";

// isSubclassOf
echo $rc->isSubclassOf('Animal') ? "yes" : "no";
echo "\n";
echo $rc->isSubclassOf('Dog') ? "yes" : "no";
echo "\n";

// interface checks
$lrc = new ReflectionClass('Logger');
echo $lrc->implementsInterface('Loggable') ? "yes" : "no";
echo "\n";

// interface as ReflectionClass
$irc = new ReflectionClass('Loggable');
echo $irc->isInterface() ? "yes" : "no";
echo "\n";
echo $irc->isInstantiable() ? "yes" : "no";
echo "\n";

// getInterfaceNames
$names = $lrc->getInterfaceNames();
echo count($names) . "\n";
echo $names[0] . "\n";

// newInstanceArgs
$arc = new ReflectionClass('Animal');
$animal = $arc->newInstanceArgs(['Buddy', 5]);
echo $animal->name . "\n";

// ReflectionFunction with user-defined function
function add(int $a, int $b = 10): int {
    return $a + $b;
}

$rf = new ReflectionFunction('add');
echo $rf->getName() . "\n";
$rfParams = $rf->getParameters();
echo count($rfParams) . "\n";
echo $rfParams[0]->getName() . "\n";
echo $rfParams[0]->getType()->getName() . "\n";
echo $rfParams[1]->isDefaultValueAvailable() ? "yes" : "no";
echo "\n";
echo $rfParams[1]->getDefaultValue() . "\n";

// number of parameters
echo $ctor->getNumberOfParameters() . "\n";
echo $ctor->getNumberOfRequiredParameters() . "\n";
