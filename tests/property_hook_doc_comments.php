<?php
// property hooks keep their doc comments, and so does a set hook's
// parameter; a promoted hooked property takes its parameter's doc comment,
// which may follow the variable
class B {
    /** prop */
    public string $p {
        /** g */
        get { return "x"; }
        /** s */
        set(string $value /** v */) {}
    }
    public string $q {
        get => "q";
    }
    public function __construct(
        /** first */
        public string $a { /** ga */ get { return "a"; } },
        public string $b /** second */ { get { return "b"; } set(string $v) {} },
        public string $c { get { return "c"; } } /** ignored */,
    ) {}
}
$rc = new ReflectionClass('B');
foreach (['p', 'q', 'a', 'b', 'c'] as $name) {
    $rp = $rc->getProperty($name);
    echo "$name: ", var_export($rp->getDocComment(), true), "\n";
    foreach ($rp->getHooks() as $type => $hook) {
        echo "  $type: ", var_export($hook->getDocComment(), true);
        foreach ($hook->getParameters() as $param) echo " param ", $param->getName(), ": ", var_export($param->getDocComment(), true);
        echo "\n";
    }
}
foreach ($rc->getConstructor()->getParameters() as $param) echo "ctor ", $param->getName(), ": ", var_export($param->getDocComment(), true), "\n";
