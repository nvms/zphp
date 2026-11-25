<?php
// enums are uncomparable (zend_objects_not_comparable): against an int,
// float, string or array they compare as 1 either way round, without the
// "could not be converted" notice; null and bool still compare first
enum Sample { case A; }
enum Backed: int { case X = 4; }
set_error_handler(function ($no, $msg) { echo "error $no: $msg\n"; return true; });
var_dump(Sample::A == 4, 4 == Sample::A, Sample::A == 0, Sample::A == "A", Sample::A == 1.5, Sample::A == []);
var_dump(Sample::A == true, Sample::A == false, Sample::A == null, null == Sample::A);
var_dump(Backed::X == 4, Backed::X < 5, Backed::X > 3, 5 > Backed::X, Sample::A <=> 4, 4 <=> Sample::A, null <=> Sample::A);
var_dump(in_array(Sample::A, [4, 0, -2, "A"]), in_array(4, [Sample::A]), in_array(Sample::A, [1, Sample::A]));
var_dump(array_search(Sample::A, [1, 2]), array_keys([0, Sample::A, "x"], 0));
var_dump(max(Sample::A, 3), min(3, Sample::A));
