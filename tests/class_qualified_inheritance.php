<?php
// Reduced PHPUnit PhpParser shape: an aliased qualified parent supplies the
// concrete implementation required by the child's interface. Autoload must
// receive the resolved name, not the literal "Node\\Stmt".
namespace QualifiedInheritance;
use QualifiedInheritance\Tree as Node;
interface Contract { public function getStartFilePos(): int; }
spl_autoload_register(function ($name) {
    echo "autoload $name\n";
    if ($name === 'QualifiedInheritance\\Tree\\Stmt') {
        eval('namespace QualifiedInheritance\\Tree; abstract class Stmt extends \\QualifiedInheritance\\Base {}');
    }
});
abstract class Base {
    public function getStartFilePos(): int { return 42; }
}
class ClassMethod extends Node\Stmt implements Contract {}
echo (new ClassMethod)->getStartFilePos(), "\n";
echo get_parent_class(ClassMethod::class), "\n";

// All declaration paths share the same rules, including the hoist prepass.
namespace QualifiedInheritance\Tree;
interface Root { public function getStartFilePos(): int; }
namespace QualifiedInheritance;
use QualifiedInheritance\Tree as Alias;
interface Derived extends Alias\Root {}
class Relative extends Tree\Stmt implements Alias\Root {}
class Absolute extends \QualifiedInheritance\Tree\Stmt implements \QualifiedInheritance\Tree\Root {}
class Local extends namespace\Tree\Stmt implements namespace\Tree\Root {}
foreach ([new Relative, new Absolute, new Local,
          new class extends Alias\Stmt implements Alias\Root {}] as $node) {
    echo $node->getStartFilePos(), "\n";
}

namespace QualifiedEarly;
use QualifiedEarly as Prefix;
class Base { public function value() { return 'early'; } }
echo (new Child)->value(), "\n";
class Child extends Prefix\Base {}
interface Root {}
interface Derived extends Prefix\Root {}
var_dump(interface_exists(Derived::class, false));
