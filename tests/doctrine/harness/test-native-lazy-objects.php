<?php

declare(strict_types=1);

use Doctrine\DBAL\DriverManager;
use Doctrine\ORM\EntityManager;
use Doctrine\ORM\Mapping as ORM;
use Doctrine\ORM\ORMSetup;
use Doctrine\ORM\Tools\SchemaTool;

require __DIR__ . '/../app/vendor/autoload.php';

#[ORM\Entity]
class LazyAccount
{
    #[ORM\Id, ORM\GeneratedValue, ORM\Column]
    private ?int $id = null;

    public function __construct(#[ORM\Column] private string $name) {}

    public function id(): ?int { return $this->id; }
    public function name(): string { return $this->name; }
    public function rename(string $name): void { $this->name = $name; }
}

function check(bool $condition, string $label): void
{
    if (!$condition) {
        throw new RuntimeException($label);
    }
    echo "$label\n";
}

$config = ORMSetup::createAttributeMetadataConfiguration([__DIR__], true);
$config->enableNativeLazyObjects(true);
$connection = DriverManager::getConnection(['driver' => 'pdo_sqlite', 'memory' => true], $config);
$em = new EntityManager($connection, $config);
(new SchemaTool($em))->createSchema([$em->getClassMetadata(LazyAccount::class)]);

$account = new LazyAccount('Ada');
$em->persist($account);
$em->flush();
$id = $account->id();
$em->clear();

$reflection = new ReflectionClass(LazyAccount::class);
$reference = $em->getReference(LazyAccount::class, $id);
check(get_class($reference) === LazyAccount::class, 'native class');
check($reflection->isUninitializedLazyObject($reference), 'reference starts lazy');
check($reference === $em->getReference(LazyAccount::class, $id), 'reference identity');
check($reference->id() === $id, 'identifier available');
check($reflection->isUninitializedLazyObject($reference), 'identifier leaves reference lazy');
$serialized = serialize($reference);
check($reflection->isUninitializedLazyObject($reference), 'serialization leaves reference lazy');
$detached = unserialize($serialized);
check($detached->id() === $id, 'serialized identifier preserved');

$connection->executeStatement('UPDATE LazyAccount SET name = ? WHERE id = ?', ['Augusta', $id]);
check($reference->name() === 'Augusta', 'first access loads current database value');
check(!$reflection->isUninitializedLazyObject($reference), 'reference initialized');
check($em->find(LazyAccount::class, $id) === $reference, 'loaded identity');
$reference->rename('Grace');
$em->flush();
$em->clear();
check($em->find(LazyAccount::class, $id)->name() === 'Grace', 'updated value persisted');

$em->clear();
$missing = $em->getReference(LazyAccount::class, 999);
$caught = false;
try {
    $missing->name();
} catch (Doctrine\ORM\EntityNotFoundException $error) {
    $caught = true;
}
check($caught, 'missing entity throws');
check($reflection->isUninitializedLazyObject($missing), 'failed load stays lazy');
check($missing->id() === 999, 'failed load preserves identifier');
$connection->executeStatement('INSERT INTO LazyAccount (id, name) VALUES (?, ?)', [999, 'Recovered']);
check($missing->name() === 'Recovered', 'failed load can retry');
check(!$reflection->isUninitializedLazyObject($missing), 'retry initializes reference');
