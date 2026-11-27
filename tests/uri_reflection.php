<?php
// the uri extension as reflection, get_class_methods and the engine see it
foreach (['Uri\Rfc3986\Uri', 'Uri\WhatWg\Url', 'Uri\Rfc3986\UriBuilder', 'Uri\WhatWg\UrlBuilder', 'Uri\WhatWg\UrlValidationError', 'Uri\WhatWg\InvalidUrlException'] as $class) {
    $r = new ReflectionClass($class);
    echo $class, ": final ", var_export($r->isFinal(), true), ", readonly ", var_export($r->isReadOnly(), true), ", internal ", var_export($r->isInternal(), true), ", extension ", $r->getExtensionName(), "\n";
    echo "  methods: ", implode(", ", get_class_methods($class)), "\n";
    foreach ($r->getProperties() as $p) echo "  property ", $p->getName(), " ", $p->getType(), $p->isReadOnly() ? " readonly" : "", "\n";
}
$m = new ReflectionMethod('Uri\WhatWg\Url', 'parse');
foreach ($m->getParameters() as $p) {
    echo $p->getPosition(), " ", $p->getName(), " ", $p->getType() ?? '-', $p->isPassedByReference() ? " &" : "", $p->isOptional() ? " optional" : "", "\n";
}
echo $m->getReturnType(), "\n";
echo (new ReflectionMethod('Uri\Rfc3986\Uri', 'equals'))->getParameters()[1]->getDefaultValueConstantName() ?? '', "\n";
try {
    (new ReflectionClass('Uri\Rfc3986\Uri'))->newInstanceWithoutConstructor();
} catch (Throwable $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
$u = new Uri\Rfc3986\Uri("https://example.com");
try {
    $u->x = 1;
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
var_dump((array) $u, get_object_vars($u), json_encode($u));
var_dump($u == new Uri\Rfc3986\Uri("https://other.example"));
var_dump(extension_loaded('uri'), function_exists('Uri\WhatWg\url_percent_encode'));
$ext = new ReflectionExtension('uri');
var_dump(array_keys($ext->getFunctions()));
try {
    Uri\WhatWg\Url::parse([]);
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
try {
    $u->equals(new Uri\WhatWg\Url("https://example.com"));
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
try {
    $u->getScheme(1);
} catch (ArgumentCountError $e) {
    echo $e->getMessage(), "\n";
}
