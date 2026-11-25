<?php
// only internal classes may implement Io\Poll\Handle
echo "start\n";
class UserHandle implements Io\Poll\Handle {}
echo "end\n";
