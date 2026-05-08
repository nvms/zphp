<?php
var_export(1e100); echo "\n";
var_export(1e-10); echo "\n";
var_export(1.5e20); echo "\n";
var_export(-2.5e-15); echo "\n";
var_export(1e0); echo "\n";

enum Status: string { case Active = 'a'; case Inactive = 'i'; }
enum Priority: int { case Low = 1; case High = 9; }
enum Plain { case Yes; case No; }

var_export(Status::Active); echo "\n";
var_export(Status::Inactive); echo "\n";
var_export(Priority::High); echo "\n";
var_export(Plain::Yes); echo "\n";
var_export([Status::Active, Priority::Low]); echo "\n";

class Box { public Status $s = Status::Active; }
var_export(new Box); echo "\n";
