<?php
// the extension each internal function, class and constant belongs to, and
// what ReflectionExtension lists for one

class UserClass implements IteratorAggregate {
    function getIterator(): Iterator { return new ArrayIterator([]); }
}
function user_function() {}
const USER_CONST = 1;

var_dump((new ReflectionClass('ArrayObject'))->getExtensionName());
var_dump((new ReflectionClass('ArrayObject'))->getExtension()->name);
var_dump((new ReflectionClass('UserClass'))->getExtensionName());
var_dump((new ReflectionClass('UserClass'))->getExtension());
var_dump((new ReflectionFunction('strlen'))->getExtensionName());
var_dump((new ReflectionFunction('json_encode'))->getExtension()->getName());
var_dump((new ReflectionFunction('user_function'))->getExtensionName());
var_dump((new ReflectionMethod('ArrayObject', 'count'))->getExtensionName());
var_dump((new ReflectionConstant('PHP_VERSION'))->getExtensionName());
var_dump((new ReflectionConstant('JSON_ERROR_NONE'))->getExtensionName());
var_dump((new ReflectionConstant('USER_CONST'))->getExtensionName());

$reflection = new ReflectionExtension('Reflection');
var_dump(array_keys($reflection->getClasses()) === $reflection->getClassNames());
var_dump(in_array('ReflectionClass', $reflection->getClassNames()));
var_dump(get_class($reflection->getClasses()['PropertyHookType']));
$json = new ReflectionExtension('json');
var_dump(isset($json->getFunctions()['json_encode']), $json->getConstants()['JSON_ERROR_NONE']);
$standard = new ReflectionExtension('standard');
var_dump(array_key_exists('user_agent', $standard->getINIEntries()));
var_dump((new ReflectionExtension('dom'))->getDependencies());
$reflection->info();

var_dump((new ReflectionClass('UserClass'))->isIterable());
var_dump((new ReflectionClass('IteratorAggregate'))->isIterateable());
var_dump((new ReflectionClass('ArrayObject'))->isIterable());
