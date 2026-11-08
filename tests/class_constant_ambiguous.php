<?php
// a constant inherited from two different declarations is ambiguous
echo "not reached\n";
interface Left { const SIDE = 'left'; }
interface Right { const SIDE = 'right'; }
class Both implements Left, Right {}
