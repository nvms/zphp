<?php
trait Visible {
    public function show(): string { return "shown"; }
    public function tell(): string { return "told"; }
}

class F {
    use Visible {
        show as protected hiddenShow;
        tell as private quietTell;
    }
}

$r = new ReflectionMethod(F::class, "hiddenShow");
echo $r->isProtected() ? "y" : "n", "\n";
echo $r->isPublic() ? "y" : "n", "\n";

$r2 = new ReflectionMethod(F::class, "quietTell");
echo $r2->isPrivate() ? "y" : "n", "\n";

$r3 = new ReflectionMethod(F::class, "show");
echo $r3->isPublic() ? "y" : "n", "\n";

trait Greeting {
    protected function hello(): string { return "hi"; }
}
class Greeter {
    use Greeting { hello as public; }
}
$g = new Greeter;
echo $g->hello(), "\n";

trait Multi1 { public function a(): string { return "a1"; } public function b(): string { return "b1"; } }
trait Multi2 { public function b(): string { return "b2"; } public function c(): string { return "c2"; } }

class J {
    use Multi1, Multi2 {
        Multi2::b insteadof Multi1;
        Multi1::b as bFromOne;
    }
}

$j = new J;
echo $j->a(), " ", $j->b(), " ", $j->c(), " ", $j->bFromOne(), "\n";

trait T1 { public function v(): string { return "T1::v"; } }
class K {
    use T1 { v as protected pv; }
}
$rm = new ReflectionMethod(K::class, "pv");
echo $rm->isProtected() ? "y" : "n", "\n";
$rm2 = new ReflectionMethod(K::class, "v");
echo $rm2->isPublic() ? "y" : "n", "\n";
