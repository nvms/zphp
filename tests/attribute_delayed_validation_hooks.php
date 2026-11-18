<?php
// #[\DelayedTargetValidation] keeps an internal attribute's validator error
// from failing the declaration; newInstance() raises it. a #[\Deprecated]
// property hook warns when it runs, and reflection names hooks "$p::get"

#[DelayedTargetValidation]
#[Attribute]
abstract class AbstractAttr {}

#[DelayedTargetValidation]
#[AllowDynamicProperties]
interface DynamicIface {}

#[DelayedTargetValidation]
#[Deprecated]
enum DeprecatedEnum {}

#[DelayedTargetValidation]
#[Attribute]
final class FineAttr {}

class Hooked {
    public string $plain {
        #[Deprecated('use other')]
        get => strtoupper($this->plain);
        #[Deprecated(since: '1.2')]
        set => $value . '!';
    }

    public string $delayed {
        #[DelayedTargetValidation]
        #[NoDiscard]
        get => 'd';
    }
}

foreach (['AbstractAttr', 'DynamicIface', 'DeprecatedEnum', 'FineAttr'] as $class) {
    $attrs = (new ReflectionClass($class))->getAttributes();
    try {
        var_dump(get_class($attrs[1]->newInstance()));
    } catch (Error $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
}

set_error_handler(function ($no, $msg) {
    echo "[$no] $msg\n";
    return true;
});
$h = new Hooked;
$h->plain = 'x';
echo $h->plain, "\n";
echo $h->delayed, "\n";

$prop = new ReflectionProperty('Hooked', 'plain');
$get = $prop->getHook(PropertyHookType::Get);
var_dump($get->getName(), $get->isDeprecated());
echo str_replace(__FILE__, "FILE", (string) $get);
echo str_replace(__FILE__, "FILE", (string) $prop->getHook(PropertyHookType::Set));

$attrs = (new ReflectionProperty('Hooked', 'delayed'))->getHook(PropertyHookType::Get)->getAttributes();
try {
    $attrs[1]->newInstance();
} catch (Error $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}
