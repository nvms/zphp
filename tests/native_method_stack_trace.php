<?php
// regression: an uncaught exception thrown from inside a native instance
// method shows 'Class->method()' at stack-trace depth #0, matching PHP.
// previously zphp's method-call dispatch sites never captured the native
// name, so the trace showed '{main}' and the temp $this frame leaked in as
// a bogus extra frame. now the IC fast path and the slow method-call paths
// record pending_native_name + pending_native_is_instance.

// IS_REPEATABLE without TARGET_ALL means the attribute can target nothing;
// ReflectionAttribute->newInstance() then throws an uncaught Error
#[Attribute(Attribute::IS_REPEATABLE)]
class Tag {
    public function __construct(public string $name) {}
}

#[Tag('a')]
class Widget {}

$rc = new ReflectionClass(Widget::class);
$attr = $rc->getAttributes()[0];
echo "attr-name: " . $attr->getName() . "\n";
// this throws from inside the native ReflectionAttribute->newInstance()
$attr->newInstance();
