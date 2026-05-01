<?php

// numeric strings of integer form preserve int type through arithmetic
var_dump("5" + 3);       // int(8)
var_dump("5" + "3");     // int(8)
var_dump("10" * "2");    // int(20)
var_dump("100" - "50");  // int(50)

// any float side promotes the result
var_dump("3.5" + 1);     // float(4.5)
var_dump("5" + "1.5");   // float(6.5)
var_dump("5" * 2.0);     // float(10)

// negative numeric strings
var_dump("-5" + 3);      // int(-2)
var_dump("+5" + 3);      // int(8)

// scientific notation in string is float
var_dump("1e2" + 1);     // float(101)
var_dump("1.5e2" + 0);   // float(150)

// trailing whitespace and leading whitespace
var_dump(" 5 " + 1);     // int(6)
var_dump("\t10" + 1);    // int(11)

// bool coerces to int
var_dump(true + 1);      // int(2)
var_dump(false + "5");   // int(5)
var_dump(true + "1.5");  // float(2.5)

// null coerces to int
var_dump(null + 5);      // int(5)
var_dump(null + 1.5);    // float(1.5)
