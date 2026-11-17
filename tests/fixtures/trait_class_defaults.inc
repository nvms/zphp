<?php
// a trait declared in another file than the classes using it
trait ElsewhereDefaults {
    public $label = self::LABEL . '!';
    public static $owner = __CLASS__;
    public $pair = [__CLASS__, self::LABEL];
}
