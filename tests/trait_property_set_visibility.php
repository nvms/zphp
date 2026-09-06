<?php
// A trait's ordinary protected property must not acquire a public write
// contract when inherited. This is Eloquent Model::$fillable's shape.
trait FillableFields {
    protected $fillable = [];
    public function fields() { return $this->fillable; }
}
class BaseRecord { use FillableFields; }
class ChildRecord extends BaseRecord {
    protected $fillable = ['title', 'body'];
}
var_dump((new ChildRecord)->fields());
trait NestedFields { use FillableFields; }
class NestedRecord { use NestedFields; }
class NestedChild extends NestedRecord {
    protected $fillable = ['nested'];
}
var_dump((new NestedChild)->fields());
// Visibility remains protected, rather than being relaxed to make the
// redeclaration pass.
$record = new ChildRecord;
try { $record->fillable = []; }
catch (Error $e) { echo "protected write rejected\n"; }
