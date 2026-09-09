<?php
// covers: #[\Deprecated] reflection, lazy object reset APIs, BcMath\Number,
// ReflectionConstant, ReflectionProperty::getSettableType, fractional
// createFromTimestamp, PHP_OUTPUT_HANDLER_* constants

namespace App\Config {
    const LIMIT = 42;
}

namespace {
    use BcMath\Number;

    function show($label, $v)
    {
        echo $label, ": ", var_export($v, true), "\n";
    }

    #[\Deprecated("use fresh()", since: "2.0")]
    function stale()
    {
        return 1;
    }
    function fresh()
    {
        return 2;
    }
    class Legacy
    {
        #[\Deprecated]
        const OLD = 1;
        const CURRENT = 2;
        #[\Deprecated(since: "1.5")]
        public function old() { return "old"; }
        public function current() { return "current"; }
    }
    show("deprecated-class", class_exists('Deprecated'));
    show("fn-deprecated", (new ReflectionFunction('stale'))->isDeprecated());
    show("fn-fresh", (new ReflectionFunction('fresh'))->isDeprecated());
    $attr = (new ReflectionFunction('stale'))->getAttributes()[0];
    show("attr-name", $attr->getName());
    $inst = $attr->newInstance();
    show("attr-message", $inst->message);
    show("attr-since", $inst->since);
    show("method-deprecated", (new ReflectionMethod('Legacy', 'old'))->isDeprecated());
    show("method-current", (new ReflectionMethod('Legacy', 'current'))->isDeprecated());
    show("method-since", (new ReflectionMethod('Legacy', 'old'))->getAttributes()[0]->newInstance()->since);
    show("const-deprecated", (new ReflectionClassConstant('Legacy', 'OLD'))->isDeprecated());
    show("const-current", (new ReflectionClassConstant('Legacy', 'CURRENT'))->isDeprecated());
    show("calls", [@stale(), fresh(), @Legacy::OLD, @(new Legacy)->old()]);

    class User
    {
        public function __construct(public int $id = 0, public string $name = "")
        {
            echo "ctor {$this->id}\n";
        }
        public function greet() { return "hi {$this->name}"; }
    }
    $rc = new ReflectionClass(User::class);
    $real = new User(1, "real");
    $rc->resetAsLazyGhost($real, function (User $u) { $u->__construct(2, "ghost"); });
    show("reset-ghost-uninit", $rc->isUninitializedLazyObject($real));
    show("reset-ghost-init", $rc->getLazyInitializer($real) instanceof Closure);
    show("reset-ghost-greet", $real->greet());
    show("reset-ghost-after", $rc->isUninitializedLazyObject($real));
    show("reset-ghost-init-after", $rc->getLazyInitializer($real));
    $proxied = new User(3, "orig");
    $rc->resetAsLazyProxy($proxied, function (User $u) { return new User(4, "proxy"); });
    show("reset-proxy-uninit", $rc->isUninitializedLazyObject($proxied));
    show("reset-proxy-name", $proxied->name);
    show("reset-proxy-after", $rc->isUninitializedLazyObject($proxied));
    $marked = $rc->newLazyGhost(fn(User $u) => $u->__construct(5, "never"));
    $rc->markLazyObjectAsInitialized($marked);
    show("marked", [$rc->isUninitializedLazyObject($marked), $rc->getLazyInitializer($marked)]);
    show("plain-init", $rc->getLazyInitializer(new User(6, "plain")));

    $p = fn(Number $n) => $n->value . "/" . $n->scale;
    show("number-parse", array_map(fn($s) => $p(new Number($s)), ["1.50", "007", "-0.50", "-0", "+3.25", "", 12]));
    show("number-add", [$p((new Number("1.5"))->add(new Number(2))), $p((new Number("1"))->add("2.25")), $p((new Number("1"))->add("2.25", 1))]);
    show("number-sub", $p((new Number(5))->sub(new Number("0.125"))));
    show("number-mul", [$p((new Number("1.5"))->mul(new Number("2.25"))), $p((new Number("3"))->mul("2.5"))]);
    $divs = [];
    foreach ([["1", "3"], ["1", "4"], ["10", "4"], ["1.5", "0.5"], ["2", "1.5"], ["1.25", "0.5"], ["1.1", "3"], ["2", "1.000000000000"]] as [$x, $y]) {
        $divs["$x/$y"] = $p((new Number($x))->div(new Number($y)));
    }
    show("number-div", $divs);
    show("number-div-scale", $p((new Number("1"))->div(3, 5)));
    show("number-mod", [$p((new Number("10"))->mod(new Number("3"))), $p((new Number("10.5"))->mod(new Number("3"))), $p((new Number("-7"))->mod(2))]);
    show("number-divmod", array_map($p, (new Number("1.5"))->divmod(new Number("0.4"))));
    show("number-powmod", $p((new Number("10"))->powmod(new Number(3), new Number(7))));
    show("number-pow", [$p((new Number("1.5"))->pow(3)), $p((new Number("2"))->pow(-2)), $p((new Number("2.5"))->pow(-1)), $p((new Number("2.5"))->pow(0)), $p((new Number("1.5"))->pow(2, 4))]);
    show("number-sqrt", [$p((new Number("2"))->sqrt()), $p((new Number("2.25"))->sqrt()), $p((new Number("2"))->sqrt(4)), $p((new Number("1.0000000000001"))->sqrt())]);
    show("number-floor-ceil", [$p((new Number("-1.5"))->floor()), $p((new Number("-1.5"))->ceil()), $p((new Number("1.5"))->floor()), $p((new Number("1.5"))->ceil())]);
    show("number-round", [
        $p((new Number("2.5"))->round()), $p((new Number("-2.5"))->round()), $p((new Number("2.55"))->round(1)), $p((new Number("25"))->round(-1)),
        $p((new Number("0.05"))->round(1)), $p((new Number("9.99"))->round(1)), $p((new Number("1.55"))->round(1, RoundingMode::HalfEven)),
        $p((new Number("1.65"))->round(1, RoundingMode::HalfEven)), $p((new Number("1.55"))->round(1, RoundingMode::TowardsZero)),
        $p((new Number("-1.55"))->round(1, RoundingMode::NegativeInfinity)), $p((new Number("1.51"))->round(1, RoundingMode::AwayFromZero)),
        $p((new Number("1.55"))->round(1, RoundingMode::HalfTowardsZero)), $p((new Number("1.45"))->round(1, RoundingMode::HalfOdd)),
    ]);
    show("number-compare", [(new Number("1.5"))->compare(new Number("1.50")), (new Number("1.5"))->compare(2), (new Number("3"))->compare("2.9")]);
    show("number-operators", [
        new Number("1.5") <=> new Number("2"), new Number("1.5") == "1.5", new Number("1.5") < 2, new Number("1.5") >= new Number("1.50"), new Number("2") != new Number("3"),
        (new Number("3") + 1)->value, (1 + new Number("3"))->value, (new Number("3") * "2.5")->value, (-(new Number("3")))->value,
        (new Number("2") ** 3)->value, (new Number("7") % 4)->value, (new Number("1") / 4)->value, (new Number("5") - new Number("0.5"))->value,
    ]);
    show("number-string", [(string) new Number("3.25"), "n=" . new Number("1.5"), json_encode(new Number("1.5")), serialize(new Number("1.5")), unserialize(serialize(new Number("2.50")))->value]);
    $n = new Number("1.5");
    show("number-props", [$n->value, $n->scale]);
    $rn = new ReflectionClass(Number::class);
    show("number-class", [$rn->isFinal(), $rn->isReadOnly()]);
    foreach (["abc", " 1", "1e5", "1.2.3"] as $bad) {
        try {
            new Number($bad);
            show("number-bad", $bad);
        } catch (ValueError $e) {
            show("number-bad", $e->getMessage());
        }
    }
    try {
        (new Number("1"))->div(new Number(0));
    } catch (DivisionByZeroError $e) {
        show("number-div-zero", $e->getMessage());
    }
    try {
        (new Number("1.5"))->pow(new Number("0.5"));
    } catch (ValueError $e) {
        show("number-pow-frac", $e->getMessage());
    }
    try {
        new Number("1") + [];
    } catch (TypeError $e) {
        show("number-type", $e->getMessage());
    }
    show("bcmod", [bcmod("10.5", "3", 1), bcmod("10.5", "3"), bcmod("1.5", "0.4", 1), bcmod("-7", "2"), bcmod("2.5", "1", 2)]);

    $c = new ReflectionConstant('App\Config\LIMIT');
    show("rconst", [$c->getName(), $c->getValue(), $c->getShortName(), $c->getNamespaceName(), $c->isDeprecated()]);
    show("rconst-global", [(new ReflectionConstant('PHP_INT_SIZE'))->getValue(), (new ReflectionConstant('PHP_EOL'))->getShortName()]);
    try {
        new ReflectionConstant('NOPE_MISSING');
    } catch (ReflectionException $e) {
        show("rconst-missing", $e->getMessage());
    }

    class Typed
    {
        public int $plain = 1;
        public private(set) string $asym = "a";
        public ?array $maybe = null;
        public $untyped;
    }
    show("settable", [
        (string) (new ReflectionProperty(Typed::class, 'plain'))->getSettableType(),
        (string) (new ReflectionProperty(Typed::class, 'asym'))->getSettableType(),
        (string) (new ReflectionProperty(Typed::class, 'maybe'))->getSettableType(),
        (new ReflectionProperty(Typed::class, 'untyped'))->getSettableType(),
    ]);

    show("ts-float", DateTimeImmutable::createFromTimestamp(1.5)->format("U.u"));
    show("ts-float-mutable", DateTime::createFromTimestamp(1700000000.25)->format("U.u"));
    show("ts-int", DateTimeImmutable::createFromTimestamp(1700000000)->format("U.u"));
    show("ts-micro", DateTime::createFromTimestamp(1.5)->getMicrosecond());

    show("output-handler", [PHP_OUTPUT_HANDLER_START, PHP_OUTPUT_HANDLER_WRITE, PHP_OUTPUT_HANDLER_FLUSH, PHP_OUTPUT_HANDLER_CLEAN, PHP_OUTPUT_HANDLER_FINAL, PHP_OUTPUT_HANDLER_CONT, PHP_OUTPUT_HANDLER_END, PHP_OUTPUT_HANDLER_CLEANABLE, PHP_OUTPUT_HANDLER_FLUSHABLE, PHP_OUTPUT_HANDLER_REMOVABLE, PHP_OUTPUT_HANDLER_STDFLAGS, PHP_OUTPUT_HANDLER_STARTED, PHP_OUTPUT_HANDLER_DISABLED, PHP_OUTPUT_HANDLER_PROCESSED]);
    show("done", true);
}
