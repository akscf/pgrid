### SpawnLocal example
[More example, primes check](SpawnLocal/example2.pl)
```
use XSpawn;
$|=1;

my @tasks = ();

#
# create  tasks
#
for(1..3) {
    my $t = spawn {
        my $task = shift;
        my $buff = undef;

        print("".$task."\n" );

        while(1) {
            $buff = $task->message_read();
	    if($buff) {
		print("recv-msg: $buff, from: parent\n");
	    }
            if($buff =~ /^PING-(\d+)/) {
                $task->message_write("PONG-".$1);
            }
            select(undef, undef, undef, 0.1);
        }
    };
    push(@tasks, $t);
}

#
# interact with the tasks
#
my $cnt = 0;
while(1) {
    foreach my $task (@tasks) {
        my $buff = $task->message_read();
        if($buff) {
            print("recv-msg: $buff, from: ".$task->pid()."\n");
        }
        $task->message_write("PING-".$cnt);
    }
    $cnt++;
    select(undef, undef, undef, 0.1);
}

```

### SpawnNet example
```
todo

```
