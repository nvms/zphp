<?php
// callable, void and never can't type a class constant
echo "not reached\n";
class Handlers { const callable HANDLER = 'strlen'; }
