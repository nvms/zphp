<?php
// unset() takes variables: a new expression is only the start of one
echo "never printed\n";
unset(new ArrayObject());
