<?php

declare(strict_types=1);

use Symfony\Component\DependencyInjection\ContainerBuilder;
use Symfony\Component\DependencyInjection\Dumper\PhpDumper;
use Symfony\Component\DependencyInjection\LazyProxy\Instantiator\LazyServiceInstantiator;

require __DIR__ . '/../app/vendor/autoload.php';

class LazyFactoryService
{
    public function __construct(public int $value) {}
    public function value(): int { return $this->value; }
    public function rename(int $value): void { $this->value = $value; }
}

class LazyServiceFactory
{
    public static int $calls = 0;
    public static ?LazyFactoryService $instance = null;

    public static function create(): LazyFactoryService
    {
        ++self::$calls;
        return self::$instance = new LazyFactoryService(42);
    }
}

function check(bool $condition, string $label): void
{
    if (!$condition) throw new RuntimeException($label);
    echo "$label\n";
}

function definition(): ContainerBuilder
{
    $builder = new ContainerBuilder();
    $builder->setProxyInstantiator(new LazyServiceInstantiator());
    $builder->register('lazy.service', LazyFactoryService::class)
        ->setFactory([LazyServiceFactory::class, 'create'])
        ->setLazy(true)
        ->setPublic(true);
    return $builder;
}

function exercise($container): void
{
    LazyServiceFactory::$calls = 0;
    LazyServiceFactory::$instance = null;
    $service = $container->get('lazy.service');
    $reflection = new ReflectionClass(LazyFactoryService::class);
    check(LazyServiceFactory::$calls === 0, 'factory deferred');
    check($reflection->isUninitializedLazyObject($service), 'proxy starts lazy');
    check($container->get('lazy.service') === $service, 'container identity');
    check($service->value() === 42, 'factory value loaded');
    check(LazyServiceFactory::$calls === 1, 'factory called once');
    check(!$reflection->isUninitializedLazyObject($service), 'proxy initialized');
    check($service !== LazyServiceFactory::$instance, 'proxy identity preserved');
    LazyServiceFactory::$instance->value = 73;
    check($service->value() === 73, 'backing writes visible');
    $service->rename(91);
    check(LazyServiceFactory::$instance->value === 91, 'proxy writes forwarded');
    check($container->get('lazy.service') === $service, 'initialized container identity');
}

exercise(definition());
$builder = definition();
$builder->compile();
$code = (new PhpDumper($builder))->dump(['class' => 'NativeLazyFactoryContainer']);
eval(substr($code, 5));
exercise(new NativeLazyFactoryContainer());
