<?php
// covers: ReflectionClass, ReflectionMethod, ReflectionParameter,
//   ReflectionNamedType, isBuiltin, getConstructor, getParameters,
//   getType, getName, isDefaultValueAvailable, getDefaultValue,
//   newInstanceArgs, isInstantiable, getParentClass, implementsInterface,
//   hasMethod, getMethods, isSubclassOf, isStatic, getDeclaringClass,
//   ReflectionFunction, getNumberOfParameters, getNumberOfRequiredParameters

interface Logger {
    public function log(string $message): void;
}

class ConsoleLogger implements Logger {
    private string $prefix;
    public function __construct(string $prefix = "[LOG]") {
        $this->prefix = $prefix;
    }
    public function log(string $message): void {
        echo $this->prefix . " " . $message . "\n";
    }
}

class Database {
    private string $dsn;
    public function __construct(string $dsn = "sqlite::memory:") {
        $this->dsn = $dsn;
    }
    public function query(string $sql): string {
        return "result from: " . $sql;
    }
    public function getDsn(): string { return $this->dsn; }
}

class UserRepository {
    private Database $db;
    private Logger $logger;
    public function __construct(Database $db, Logger $logger) {
        $this->db = $db;
        $this->logger = $logger;
    }
    public function find(int $id): string {
        $this->logger->log("finding user $id");
        return $this->db->query("SELECT * FROM users WHERE id = $id");
    }
}

class Container {
    private array $bindings = [];
    private array $instances = [];

    public function bind(string $abstract, string $concrete): void {
        $this->bindings[$abstract] = $concrete;
    }

    public function singleton(string $abstract, string $concrete): void {
        $this->bindings[$abstract] = $concrete;
        $this->instances[$abstract] = null;
    }

    public function make(string $abstract): object {
        if (isset($this->instances[$abstract]) && $this->instances[$abstract] !== null) {
            return $this->instances[$abstract];
        }

        $concrete = $this->bindings[$abstract] ?? $abstract;
        $object = $this->build($concrete);

        if (array_key_exists($abstract, $this->instances)) {
            $this->instances[$abstract] = $object;
        }

        return $object;
    }

    private function build(string $concrete): object {
        $reflector = new ReflectionClass($concrete);

        if (!$reflector->isInstantiable()) {
            echo "ERROR: $concrete is not instantiable\n";
            return new \stdClass();
        }

        $constructor = $reflector->getConstructor();
        if ($constructor === null) {
            return $reflector->newInstanceArgs([]);
        }

        $parameters = $constructor->getParameters();
        $resolved = [];

        foreach ($parameters as $param) {
            $type = $param->getType();

            if ($type !== null && !$type->isBuiltin()) {
                $resolved[] = $this->make($type->getName());
            } elseif ($param->isDefaultValueAvailable()) {
                $resolved[] = $param->getDefaultValue();
            } else {
                echo "ERROR: cannot resolve param " . $param->getName() . "\n";
                $resolved[] = null;
            }
        }

        return $reflector->newInstanceArgs($resolved);
    }
}

// wire up the container
$container = new Container();
$container->bind('Logger', 'ConsoleLogger');
$container->singleton('Database', 'Database');

// resolve a complex dependency tree
$repo = $container->make('UserRepository');
echo $repo->find(42) . "\n";

// singleton check - same instance
$db1 = $container->make('Database');
$db2 = $container->make('Database');
echo ($db1 === $db2 ? "same" : "different") . " instance\n";

// reflection introspection
$rc = new ReflectionClass('UserRepository');
echo "class: " . $rc->getName() . "\n";
echo "methods: " . count($rc->getMethods()) . "\n";
echo "has find: " . ($rc->hasMethod('find') ? "yes" : "no") . "\n";

$find = $rc->getMethod('find');
echo "find is public: " . ($find->isPublic() ? "yes" : "no") . "\n";
echo "find is static: " . ($find->isStatic() ? "yes" : "no") . "\n";
echo "find params: " . $find->getNumberOfParameters() . "\n";

$ctor = $rc->getConstructor();
echo "constructor declaring class: " . $ctor->getDeclaringClass()->getName() . "\n";
echo "constructor required params: " . $ctor->getNumberOfRequiredParameters() . "\n";

// ReflectionFunction
function greet(string $name, string $greeting = "Hello"): string {
    return "$greeting, $name!";
}

$rf = new ReflectionFunction('greet');
echo "function: " . $rf->getName() . "\n";
echo "params: " . $rf->getNumberOfParameters() . "\n";
echo "required: " . $rf->getNumberOfRequiredParameters() . "\n";

$params = $rf->getParameters();
foreach ($params as $p) {
    echo "  " . $p->getName();
    if ($p->hasType()) {
        echo " (" . $p->getType()->getName() . ")";
    }
    if ($p->isDefaultValueAvailable()) {
        echo " = " . $p->getDefaultValue();
    }
    echo "\n";
}

// parent class and interface checks
$drc = new ReflectionClass('Database');
echo "Database parent: " . ($drc->getParentClass() === false ? "none" : $drc->getParentClass()->getName()) . "\n";

$lrc = new ReflectionClass('ConsoleLogger');
echo "ConsoleLogger implements Logger: " . ($lrc->implementsInterface('Logger') ? "yes" : "no") . "\n";

$irc = new ReflectionClass('Logger');
echo "Logger is interface: " . ($irc->isInterface() ? "yes" : "no") . "\n";
echo "Logger is instantiable: " . ($irc->isInstantiable() ? "yes" : "no") . "\n";
