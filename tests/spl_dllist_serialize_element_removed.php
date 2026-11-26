<?php

class RemoveSelf {
    public function __serialize(): array {
        global $list;
        unset($list[0]);
        return [];
    }
}

$list = new SplDoublyLinkedList();
$list->push([new RemoveSelf(), [1, 2, 3]]);
$list->push("tail");
var_dump($list->serialize());
var_dump($list->count());

class RemoveNext {
    public function __serialize(): array {
        global $list2;
        unset($list2[1]);
        return [];
    }
}

$list2 = new SplDoublyLinkedList();
$list2->push(new RemoveNext());
$list2->push("removed");
$list2->push("after");
var_dump($list2->serialize());
var_dump($list2->count());

class RemoveAll {
    public function __serialize(): array {
        global $list3;
        while (!$list3->isEmpty()) {
            $list3->pop();
        }
        return [];
    }
}

$list3 = new SplDoublyLinkedList();
$list3->push([new RemoveAll(), [1, 2]]);
$list3->push("x");
$list3->push("y");
var_dump($list3->serialize());
var_dump($list3->count());

class RemoveHolder {
    public function __serialize(): array {
        global $list4;
        unset($list4[0]);
        return [];
    }
}

class Holder {
    public $first;
    public $second = "second";
    public $third = "third";
}

$holder = new Holder();
$holder->first = new RemoveHolder();

$list4 = new SplDoublyLinkedList();
$list4->push($holder);
unset($holder);
$list4->push("tail");
var_dump($list4->serialize());
var_dump($list4->count());

?>
