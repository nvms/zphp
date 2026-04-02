<?php
// covers: ReflectionClass (getName, getMethods, getProperties, getMethod,
//   getProperty, getParentClass, getInterfaceNames, hasMethod, isInterface,
//   getAttributes), ReflectionMethod (getName, getParameters, isPublic,
//   isPrivate, isProtected, isStatic, getAttributes),
//   ReflectionProperty (getName, isPublic, isPrivate, isProtected, isDefault,
//   getAttributes), ReflectionParameter (getName, getPosition, isOptional,
//   hasType, getType), ReflectionAttribute (getName, getArguments,
//   newInstance), class hierarchy reflection, interface detection,
//   practical object introspection, PHP 8 attributes

interface Loggable {
    public function logEntry(): string;
}

interface Taggable {
    public function getTags(): array;
}

class BaseEntity {
    protected int $id;
    public function __construct(int $id) {
        $this->id = $id;
    }
    public function getId(): int {
        return $this->id;
    }
}

class User extends BaseEntity implements Loggable, Taggable {
    public string $name;
    public string $email;
    private string $password;
    protected int $loginCount = 0;

    public function __construct(int $id, string $name, string $email) {
        parent::__construct($id);
        $this->name = $name;
        $this->email = $email;
        $this->password = 'hashed';
    }

    public function logEntry(): string {
        return "User:{$this->id}:{$this->name}";
    }

    public function getTags(): array {
        return ['user', 'entity'];
    }

    public function greet(string $greeting = 'Hello'): string {
        return "{$greeting}, {$this->name}!";
    }

    private function hashPassword(): string {
        return md5($this->password);
    }

    protected function incrementLogin(): void {
        $this->loginCount++;
    }

    public static function fromArray(array $data): self {
        return new self($data['id'], $data['name'], $data['email']);
    }
}

// --- ReflectionClass basics ---

echo "=== ReflectionClass ===\n";

$ref = new ReflectionClass('User');
echo "name: " . $ref->getName() . "\n";

$parent = $ref->getParentClass();
echo "parent: " . ($parent ? $parent->getName() : 'none') . "\n";

$interfaces = $ref->getInterfaceNames();
sort($interfaces);
echo "interfaces: " . implode(', ', $interfaces) . "\n";

$ifRef = new ReflectionClass('Loggable');
echo "Loggable isInterface: " . ($ifRef->isInterface() ? 'true' : 'false') . "\n";

echo "hasMethod greet: " . ($ref->hasMethod('greet') ? 'true' : 'false') . "\n";
echo "hasMethod nonexistent: " . ($ref->hasMethod('nonexistent') ? 'true' : 'false') . "\n";

// --- methods ---

echo "\n=== Methods ===\n";

$methods = $ref->getMethods();
$methodNames = [];
foreach ($methods as $m) {
    $methodNames[] = $m->getName();
}
sort($methodNames);
echo "all methods: " . implode(', ', $methodNames) . "\n";
echo "method count: " . count($methodNames) . "\n";

// --- method visibility ---

echo "\n=== Method Visibility ===\n";

$greet = $ref->getMethod('greet');
echo "greet isPublic: " . ($greet->isPublic() ? 'true' : 'false') . "\n";
echo "greet isPrivate: " . ($greet->isPrivate() ? 'true' : 'false') . "\n";
echo "greet isProtected: " . ($greet->isProtected() ? 'true' : 'false') . "\n";
echo "greet isStatic: " . ($greet->isStatic() ? 'true' : 'false') . "\n";

$hash = $ref->getMethod('hashPassword');
echo "hashPassword isPublic: " . ($hash->isPublic() ? 'true' : 'false') . "\n";
echo "hashPassword isPrivate: " . ($hash->isPrivate() ? 'true' : 'false') . "\n";

$incLogin = $ref->getMethod('incrementLogin');
echo "incrementLogin isProtected: " . ($incLogin->isProtected() ? 'true' : 'false') . "\n";

$createM = $ref->getMethod('fromArray');
echo "fromArray isStatic: " . ($createM->isStatic() ? 'true' : 'false') . "\n";

// --- parameters ---

echo "\n=== Parameters ===\n";

$greetParams = $greet->getParameters();
echo "greet param count: " . count($greetParams) . "\n";
foreach ($greetParams as $p) {
    $line = "  " . $p->getName() . " pos=" . $p->getPosition();
    $line .= " optional=" . ($p->isOptional() ? 'true' : 'false');
    echo $line . "\n";
}

$fromArrayParams = $createM->getParameters();
echo "fromArray param count: " . count($fromArrayParams) . "\n";
foreach ($fromArrayParams as $p) {
    $line = "  " . $p->getName() . " pos=" . $p->getPosition();
    if ($p->hasType()) {
        $line .= " type=" . $p->getType()->getName();
    }
    echo $line . "\n";
}

// --- properties ---

echo "\n=== Properties ===\n";

$props = $ref->getProperties();
$propInfo = [];
foreach ($props as $p) {
    $vis = 'public';
    if ($p->isPrivate()) $vis = 'private';
    if ($p->isProtected()) $vis = 'protected';
    $propInfo[] = $p->getName() . ":" . $vis;
}
sort($propInfo);
echo "properties: " . implode(', ', $propInfo) . "\n";
echo "property count: " . count($propInfo) . "\n";

$nameProp = $ref->getProperty('name');
echo "\nname isPublic: " . ($nameProp->isPublic() ? 'true' : 'false') . "\n";
echo "name isDefault: " . ($nameProp->isDefault() ? 'true' : 'false') . "\n";

$pwdProp = $ref->getProperty('password');
echo "password isPrivate: " . ($pwdProp->isPrivate() ? 'true' : 'false') . "\n";

// --- practical: object inspector ---

echo "\n=== Object Inspector ===\n";

function inspect(object $obj): void {
    $ref = new ReflectionClass(get_class($obj));
    echo "Class: " . $ref->getName() . "\n";

    $parent = $ref->getParentClass();
    if ($parent) echo "  extends: " . $parent->getName() . "\n";

    $ifaces = $ref->getInterfaceNames();
    if (count($ifaces) > 0) {
        sort($ifaces);
        echo "  implements: " . implode(', ', $ifaces) . "\n";
    }

    $publicMethods = [];
    foreach ($ref->getMethods() as $m) {
        if ($m->isPublic() && $m->getName() !== '__construct') {
            $paramCount = count($m->getParameters());
            $publicMethods[] = $m->getName() . "({$paramCount})";
        }
    }
    sort($publicMethods);
    echo "  public methods: " . implode(', ', $publicMethods) . "\n";

    $publicProps = [];
    foreach ($ref->getProperties() as $p) {
        if ($p->isPublic()) {
            $publicProps[] = $p->getName();
        }
    }
    sort($publicProps);
    echo "  public properties: " . implode(', ', $publicProps) . "\n";
}

$user = new User(1, 'Alice', 'alice@example.com');
inspect($user);

// --- Attributes ---

echo "\n=== Attributes ===\n";

#[Attribute]
class Route {
    public function __construct(
        public string $path = '',
        public string $method = 'GET'
    ) {}
}

#[Attribute]
class Middleware {
    public function __construct(public string $name = '') {}
}

#[Attribute]
class Column {
    public function __construct(public string $type = 'string') {}
}

#[Route('/api/users')]
#[Middleware('auth')]
class UserController {
    #[Column('varchar')]
    public string $title = '';

    #[Route('/list')]
    public function list() { return []; }

    #[Route('/create', method: 'POST')]
    public function create() { return 'created'; }
}

$rc = new ReflectionClass('UserController');
$classAttrs = $rc->getAttributes();
echo "class attr count: " . count($classAttrs) . "\n";
echo "class attr 0: " . $classAttrs[0]->getName() . "\n";
echo "class attr 0 args: " . count($classAttrs[0]->getArguments()) . "\n";
echo "class attr 0 arg 0: " . $classAttrs[0]->getArguments()[0] . "\n";
echo "class attr 1: " . $classAttrs[1]->getName() . "\n";

$listMethod = $rc->getMethod('list');
$listAttrs = $listMethod->getAttributes();
echo "list attr count: " . count($listAttrs) . "\n";
echo "list attr 0: " . $listAttrs[0]->getName() . "\n";

$createMethod = $rc->getMethod('create');
$createAttrs = $createMethod->getAttributes();
echo "create attr count: " . count($createAttrs) . "\n";
echo "create attr 0: " . $createAttrs[0]->getName() . "\n";
echo "create attr arg 0: " . $createAttrs[0]->getArguments()[0] . "\n";

$titleProp = $rc->getProperty('title');
$titleAttrs = $titleProp->getAttributes();
echo "title attr count: " . count($titleAttrs) . "\n";
echo "title attr 0: " . $titleAttrs[0]->getName() . "\n";
echo "title attr 0 arg: " . $titleAttrs[0]->getArguments()[0] . "\n";

// newInstance
$routeAttr = $classAttrs[0];
$routeInstance = $routeAttr->newInstance();
echo "route instance class: " . get_class($routeInstance) . "\n";
echo "route instance path: " . $routeInstance->path . "\n";

echo "\nDone.\n";
