<?php
abstract class AbstractHookMetadata {
    abstract public string $name { get; set; }
}
class FinalHookMetadata {
    public int $number = 1 { final get => $this->number; set(string|int $input) { $this->number = (int)$input; } }
    public ?string $text { set {} }
}
trait FinalHookMetadataTrait {
    public int $value { final get => 42; }
}
class UsesHookMetadataTrait { use FinalHookMetadataTrait; }
foreach ([AbstractHookMetadata::class => ['name'], FinalHookMetadata::class => ['number', 'text'], UsesHookMetadataTrait::class => ['value']] as $class => $names) {
    foreach ($names as $name) {
        $rp = new ReflectionProperty($class, $name);
        echo $class, ':', $name, ':', (int)$rp->hasHooks(), ':', (int)$rp->isAbstract(), "\n";
        foreach ($rp->getHooks() as $kind => $hook) {
            echo $kind, ':', (int)$hook->isAbstract(), ':', (int)$hook->isFinal(), ':', $hook->getModifiers(), ':', (string)$hook->getReturnType(), "\n";
            foreach ($hook->getParameters() as $p) echo $p->getName(), ':', (int)$p->hasType(), ':', (string)$p->getType(), ':', (int)$p->allowsNull(), "\n";
        }
    }
}

class ConcreteHookMetadata extends AbstractHookMetadata {
    public string $name { get => 'implemented'; set {} }
}
$implemented = new ReflectionProperty(ConcreteHookMetadata::class, 'name');
echo (int)$implemented->isAbstract(), ':', (new ConcreteHookMetadata)->name, "\n";
