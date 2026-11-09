<?php
// reflectors keep their state internally: var_dump, print_r, var_export,
// (array) and get_object_vars show only the name (and class for members),
// and the string forms of properties, constants, parameters and attributes

#[Attribute(Attribute::TARGET_ALL)]
class Column
{
    public function __construct(public string $name, public int $length = 255, public array $options = []) {}
}

enum Level: int
{
    case Debug = 100;
    case Error = 400;
}

class Invoice
{
    const STATUS_DRAFT = 'draft';
    /** Cents per unit. */
    final protected const UNIT = 100;
    const RATE = 0.19;

    #[Column('total', length: 12, options: ['unsigned' => true])]
    public int $total = 0;
    protected ?string $note = null;
    public static array $registry = [];
    public private(set) string $number = 'INV-0';
    public readonly float $tax;

    public function __construct(public string $customer = 'anonymous', float $tax = 0.19)
    {
        $this->tax = $tax;
    }

    #[Column('lines')]
    public function addLine(string $item, int $qty = 1, float $price = 0.0, Level $level = Level::Debug): static
    {
        return $this;
    }
}

function format_amount(int $cents, string $currency = 'EUR'): string
{
    return sprintf('%.2f %s', $cents / 100, $currency);
}

$addLine = new ReflectionMethod('Invoice', 'addLine');
$cents = new ReflectionParameter('format_amount', 0);
$note = new ReflectionProperty('Invoice', 'note');
$reflectors = [
    new ReflectionClass('Invoice'),
    new ReflectionObject(new Invoice()),
    new ReflectionMethod('Invoice', 'addLine'),
    new ReflectionFunction('format_amount'),
    new ReflectionParameter('format_amount', 1),
    new ReflectionProperty('Invoice', 'total'),
    new ReflectionClassConstant('Invoice', 'UNIT'),
    new ReflectionEnum('Level'),
    new ReflectionEnumBackedCase('Level', 'Error'),
    $addLine->getReturnType(),
    $cents->getType(),
    $note->getType(),
    new ReflectionFunction(function (int $x) { return $x; }),
];

foreach ($reflectors as $r) {
    var_dump($r);
    print_r($r);
    echo "\n";
    var_dump((array) $r);
    var_dump(get_object_vars($r));
    echo json_encode($r), "\n";
}
var_export(new ReflectionProperty('Invoice', 'note'));
echo "\n";
var_export(new ReflectionMethod('Invoice', 'addLine'));
echo "\n";
foreach (new ReflectionProperty('Invoice', 'total') as $k => $v) {
    echo "$k => $v\n";
}

// string forms of the member reflectors
foreach (['total', 'note', 'registry', 'number', 'tax', 'customer'] as $name) {
    echo new ReflectionProperty('Invoice', $name);
}
foreach (['STATUS_DRAFT', 'UNIT', 'RATE'] as $name) {
    echo new ReflectionClassConstant('Invoice', $name);
}
echo new ReflectionEnumBackedCase('Level', 'Debug');
foreach ((new ReflectionMethod('Invoice', 'addLine'))->getParameters() as $p) {
    echo $p, "\n";
}
foreach ((new ReflectionProperty('Invoice', 'total'))->getAttributes() as $attribute) {
    echo $attribute;
}
foreach ((new ReflectionMethod('Invoice', 'addLine'))->getAttributes() as $attribute) {
    echo $attribute;
}
echo (new ReflectionClass('Column'))->getAttributes()[0];
echo new ReflectionConstant('PHP_INT_SIZE');
echo new ReflectionConstant('E_ALL');
define('APP_ENV', 'test');
echo new ReflectionConstant('APP_ENV');

// declared here, as php creates an enum case object when a constant first
// needs it
if (true) {
    class Settings
    {
        public const Level DEFAULT_LEVEL = Level::Error;
        const LEVELS = [Level::Debug, Level::Error];
    }
}
echo new ReflectionClassConstant('Settings', 'DEFAULT_LEVEL');
echo new ReflectionClassConstant('Settings', 'LEVELS');
