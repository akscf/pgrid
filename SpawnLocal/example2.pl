#!/usr/bin/perl -I./
use XSpawn;
$|=1;

#
# Primes
#
sub is_prime {
    my ($num) = @_;
    my ($sqrt, $d) = (sqrt($num), 2);
    while(1) {
	if( $num % $d == 0 ) { return 0; }
	if( $d > $sqrt ) { return 1; }
	$d++;
    }
}

# ------------------------------------------------------------------------------------------------------------------
print("[$$] - parent\n");
my @tasks = ();
for(1..20) {
    my $t = spawn {
        my $task = shift;
        my $buff = undef;
	my $n1=0, $n2=0;
	my @primes;

	# send ready to parent
	$task->message_write("READY");

	# wait for parent commands
        while(1) {
            $buff = $task->message_read();
            if($buff =~ /^START\:(\d+)\-(\d+)/) { 
		$n1 = $1; $n2= $2; 
		last; 
	    }
	    select(undef, undef, undef, 0.1); 
        }

	# generate and check range
	print("[$$] ==> ($n1 ... $n2)\n");
	while($n1 < $n2) {
	    if(is_prime($n1)) { push(@primes, $n1); }
	    $n1++;	
	}
	$task->message_write("DONE:[".join(',', @primes)."]");

	# wait for a parent
	while(1) {
	    $buff = $task->message_read();
	    last if($buff =~ /^EXIT/);
	    select(undef, undef, undef, 0.1); 
	}
    };
    push(@tasks, $t);
}

# ------------------------------------------------------------------------------------------------------------------
my $jdone = 0;
my $pnum = 1000;
while(1) {
    foreach my $task (@tasks) {
	next if($task->is_destroyed());

        my $buff = $task->message_read();
	if($buff =~ /^READY/) { 
	    my $pend = $pnum + 1000;
	    $task->message_write("START:$pnum-$pend");
	    $pnum = $pend + 1;
	}
	if($buff =~ /^DONE:\[(.*)\]/) {
	    my $primes = $1;
	    print("[".$task->pid()."] RESULT=($primes)\n");
	    $task->message_write("EXIT");
    	    $jdone++;
	}
    }
    last if($jdone >= scalar(@tasks));
    select(undef, undef, undef, 0.1);
}

print("*** DONE ***\n");
