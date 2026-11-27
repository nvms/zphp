<?php
// an enum's traits are listed as a class's are
namespace App;

trait Labels { function label() { return ucfirst(strtolower($this->name)); } }
trait Describes { function describe() { return static::class . '::' . $this->name; } }

enum Status { use Labels, \App\Describes; case ACTIVE; case INACTIVE; }

var_dump(class_uses(Status::class), class_uses(Status::ACTIVE));
var_dump((new \ReflectionClass(Status::class))->getTraitNames());
var_dump(array_keys((new \ReflectionEnum(Status::class))->getTraits()));
echo Status::INACTIVE->label(), ' ', Status::ACTIVE->describe(), "\n";
