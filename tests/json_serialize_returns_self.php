<?php
// a JsonSerializable object that returns itself is encoded by its properties
class Point implements JsonSerializable {
    public $x = 1;
    protected $hidden = 2;
    public $y = [3];
    public function jsonSerialize(): mixed { return $this; }
}
var_dump(json_encode(new Point));
var_dump(json_encode(['p' => new Point]));
