<?php
// a nested write through a user offsetGet keeps the value being written
// alive while offsetGet runs
class Grid extends SplFixedArray {
    public function offsetGet($index): mixed {
        $row = parent::offsetGet($index);
        return $row;
    }
}
$grid = new Grid(2);
$grid[0] = new Grid(2);
$grid[0][1] = new Grid(3);
$grid[0][0] = 'cell';
var_dump($grid[0][1]->getSize(), $grid[0][0], isset($grid[0][1][2]), $grid[0][1][2] ?? 'none');
