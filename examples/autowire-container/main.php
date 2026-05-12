<?php
// covers: autowiring DI container using reflection on promoted ctor params,
//   typed-property hydration, interface binding, ReflectionNamedType::isBuiltin,
//   ReflectionParameter::isPromoted - the heart of Symfony/Laravel container code

interface Logger { public function info(string $msg): void; }
interface Mailer { public function send(string $to, string $body): void; }

class ConsoleLogger implements Logger {
    public array $log = [];
    public function info(string $msg): void { $this->log[] = $msg; }
}

class ArrayMailer implements Mailer {
    public array $outbox = [];
    public function send(string $to, string $body): void {
        $this->outbox[] = ['to' => $to, 'body' => $body];
    }
}

class WelcomeService {
    public function __construct(
        public Logger $log,
        public Mailer $mail,
        public string $tagline = 'Welcome!',
        public int $retries = 3,
    ) {}

    public function welcome(string $email): void {
        $this->log->info("welcoming $email");
        $this->mail->send($email, $this->tagline);
    }
}

final class Container {
    private array $factories = [];
    private array $instances = [];

    public function bind(string $abstract, callable $factory): void {
        $this->factories[$abstract] = $factory;
    }

    public function get(string $type): object {
        if (isset($this->instances[$type])) return $this->instances[$type];
        if (isset($this->factories[$type])) {
            $obj = ($this->factories[$type])($this);
            $this->instances[$type] = $obj;
            return $obj;
        }
        $rc = new ReflectionClass($type);
        if ($rc->isAbstract() or $rc->isInterface()) {
            throw new RuntimeException("Cannot autowire $type without a binding");
        }
        $ctor = $rc->getConstructor();
        if ($ctor === null) {
            $obj = $rc->newInstance();
        } else {
            $args = [];
            foreach ($ctor->getParameters() as $p) {
                $args[] = $this->resolveParam($p);
            }
            $obj = $rc->newInstanceArgs($args);
        }
        $this->instances[$type] = $obj;
        return $obj;
    }

    private function resolveParam(ReflectionParameter $p): mixed {
        $t = $p->getType();
        if ($t instanceof ReflectionNamedType && !$t->isBuiltin()) {
            return $this->get($t->getName());
        }
        if ($p->isDefaultValueAvailable()) return $p->getDefaultValue();
        if ($t instanceof ReflectionNamedType && $t->allowsNull()) return null;
        throw new RuntimeException("Cannot resolve \${$p->getName()}");
    }
}

echo "=== autowire concrete with interface deps ===\n";
$c = new Container();
$c->bind(Logger::class, fn() => new ConsoleLogger());
$c->bind(Mailer::class, fn() => new ArrayMailer());

$svc = $c->get(WelcomeService::class);
echo "got: " . get_class($svc) . "\n";
echo "log is ConsoleLogger: " . ($svc->log instanceof ConsoleLogger ? "yes" : "no") . "\n";
echo "mail is ArrayMailer: " . ($svc->mail instanceof ArrayMailer ? "yes" : "no") . "\n";
echo "tagline default: " . $svc->tagline . "\n";
echo "retries default: " . $svc->retries . "\n";

echo "\n=== exercise the wired service ===\n";
$svc->welcome('alice@example.com');
$svc->welcome('bob@example.com');
echo "log count: " . count($svc->log->log) . "\n";
echo "outbox count: " . count($svc->mail->outbox) . "\n";
echo "first email to: " . $svc->mail->outbox[0]['to'] . "\n";

echo "\n=== singleton behavior ===\n";
$a = $c->get(WelcomeService::class);
$b = $c->get(WelcomeService::class);
echo "same instance: " . ($a === $b ? "yes" : "no") . "\n";

echo "\n=== hydrate DTO from array via reflection ===\n";
class Order {
    public function __construct(
        public readonly int $id,
        public readonly string $customer,
        public readonly float $total,
        public readonly bool $paid = false,
    ) {}
}

function hydrate(string $class, array $data): object {
    $rc = new ReflectionClass($class);
    $ctor = $rc->getConstructor();
    $args = [];
    foreach ($ctor->getParameters() as $p) {
        $name = $p->getName();
        if (array_key_exists($name, $data)) {
            $args[] = $data[$name];
        } elseif ($p->isDefaultValueAvailable()) {
            $args[] = $p->getDefaultValue();
        } else {
            throw new RuntimeException("missing $name");
        }
    }
    return $rc->newInstanceArgs($args);
}

$order = hydrate(Order::class, [
    'id' => 42,
    'customer' => 'Alice',
    'total' => 99.95,
]);
echo "id: $order->id customer: $order->customer total: $order->total paid: " . var_export($order->paid, true) . "\n";

echo "\n=== missing binding fails cleanly ===\n";
class Unresolvable {
    public function __construct(public Logger $log, public string $required) {}
}
$c2 = new Container();
$c2->bind(Logger::class, fn() => new ConsoleLogger());
try {
    $c2->get(Unresolvable::class);
    echo "no throw\n";
} catch (RuntimeException $e) {
    echo "caught: " . $e->getMessage() . "\n";
}

echo "\n=== promoted readonly props are reflected with types ===\n";
$rc = new ReflectionClass(Order::class);
foreach ($rc->getProperties() as $p) {
    $t = $p->getType();
    $tname = $t instanceof ReflectionNamedType ? $t->getName() : '?';
    $ro = $p->isReadOnly() ? 'readonly ' : '';
    echo "  {$ro}{$tname} \${$p->getName()}\n";
}

echo "\n=== ctor params via reflection ===\n";
$ctor = $rc->getConstructor();
foreach ($ctor->getParameters() as $p) {
    $t = $p->getType();
    $tname = $t instanceof ReflectionNamedType ? $t->getName() : '?';
    $promo = $p->isPromoted() ? ' [promoted]' : '';
    $built = $t instanceof ReflectionNamedType && $t->isBuiltin() ? ' builtin' : '';
    echo "  $tname$built \${$p->getName()}$promo\n";
}

echo "\ndone\n";
