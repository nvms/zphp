<?php
interface ICan {
    public function action(): string;
    public function more(int $x): bool;
}

$r = new ReflectionClass(ICan::class);
echo $r->isInterface() ? "y" : "n", "\n";
foreach ($r->getMethods() as $m) {
    echo $m->getName(), " ";
    echo $m->isAbstract() ? "abs " : "";
    echo $m->isPublic() ? "pub " : "";
    echo "\n";
}

echo $r->hasMethod("action") ? "y" : "n", "\n";
echo $r->hasMethod("doesnotexist") ? "y" : "n", "\n";

$m = $r->getMethod("more");
echo $m->getName(), "\n";
echo $m->isAbstract() ? "y" : "n", "\n";
