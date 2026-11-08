<?php
// zend.enable_gc and gc_enable()/gc_disable() are one setting: turning it
// off in either stops the automatic cycle collector
class C { public $self; function __construct() { $this->self = $this; } }
var_dump(ini_get('zend.enable_gc'), gc_enabled());
gc_disable();
var_dump(ini_get('zend.enable_gc'), gc_enabled());
gc_enable();
var_dump(ini_get('zend.enable_gc'), gc_enabled());
var_dump(ini_set('zend.enable_gc', '0'), ini_get('zend.enable_gc'), gc_enabled());
$runs = gc_status()['runs'];
for ($i = 0; $i < 50000; $i++) new C;
var_dump(gc_status()['runs'] === $runs);
var_dump(ini_set('zend.enable_gc', 'on'), gc_enabled());
ini_set('zend.enable_gc', 'off');
var_dump(gc_enabled());
ini_restore('zend.enable_gc');
var_dump(ini_get('zend.enable_gc'), gc_enabled());
for ($i = 0; $i < 50000; $i++) new C;
var_dump(gc_status()['runs'] > $runs);
var_dump(gc_collect_cycles() >= 0);
