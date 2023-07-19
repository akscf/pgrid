#!/usr/bin/perl -I./
use XSpawn;
use Data::Dumper;

$|=1;

#
# Simple ping-pong 
#

my @tasks = ();

for(1..3) {
    my $t = spawn {
        my $task = shift;
        my $buff = undef;
        my $x = 1+1+2;

        print($task." -- started\n" );

        while(1) {
            $buff = $task->message_read();
	    if($buff) {
                print("$$ recv-msg: $buff, from: main\n");
            }
            if($buff =~ /^PING-(\d+)/) {
                $task->message_write("PONG-".$1);
            }
	    select(undef, undef, undef, 0.1); 
        }
    };
    push(@tasks, $t);
}

my $cnt = 0;
while(1) {
    foreach my $task (@tasks) {
        my $buff = $task->message_read();
        if($buff) {
            print("main: recv-msg: $buff, from: ".$task->pid()."\n");
        }
        $task->message_write("PING-".$cnt);
    }
    $cnt++;
    select(undef, undef, undef, 0.1);
}
