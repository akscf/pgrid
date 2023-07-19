package XSpawn;
#
# Standalone version
# (C) aks
#
use 5.006;
our $VERSION = '0.1';

use strict;
use warnings;

use Exporter 5.57 'import';
our @EXPORT = our @EXPORT_OK = qw(spawn);

use Carp;
$Carp::Internal{+__PACKAGE__}++;

use POSIX;
use Sys::Hostname;

my %glb_childs  = ();        # all pids (pid => obj)
my $glb_node_id = hostname;  # current host name
my $glb_last_fault = undef;

BEGIN {
  my $su = $INC{'Sub/Util.pm'} && defined &Sub::Util::set_subname;
  my $sn = $INC{'Sub/Name.pm'} && eval { Sub::Name->VERSION(0.08) };
  unless ($su || $sn) {
    $su = eval { require Sub::Util; } && defined &Sub::Util::set_subname;
    unless ($su) {
      $sn = eval { require Sub::Name; Sub::Name->VERSION(0.08) };
    }
  }
  *_subname = $su ? \&Sub::Util::set_subname : $sn ? \&Sub::Name::subname : sub { $_[1] };
  *_HAS_SUBNAME = ($su || $sn) ? sub(){1} : sub(){0};
  
  $glb_node_id = hostname;

  $SIG{CHLD} = sub {
    while( ( my $pid = waitpid( -1, &WNOHANG ) ) > 0 ) {
      task_delete( $glb_childs{ $pid } );
    }
  };

  $SIG{INT} = $SIG{TERM} = sub {
    foreach my $pid (keys %glb_childs) {
      task_delete( $glb_childs{ $pid } );
    }
    exit 0;
  };

}

# ---------------------------------------------------------------------------------------------------------------------------------------------------------------
# public
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------
sub spawn (&;@) {
  my ( $scode, @dst_nodes ) = @_;
  
  _subname(caller().'::spawn {...} ' => $scode) if _HAS_SUBNAME;

  my $task = XSpawn::Task->new($glb_node_id);
  my $failed = not eval {
      if($task->do_fork() == 1) { 
        $scode->($task);
	exit 0;
      }
      $glb_childs{ $task->pid() } = $task;
  };

  $glb_last_fault = $@;
  return undef if($glb_last_fault);
  return $task;
}

# get and clean
sub get_last_fault {
    my $err = $glb_last_fault;
    $glb_last_fault = undef;
    return $err;
}

# ---------------------------------------------------------------------------------------------------------------------------------------------------------------
# private
# ---------------------------------------------------------------------------------------------------------------------------------------------------------------
sub task_delete {
    my ( $task ) = @_;
    if($task) {
        $task->cleanup();
        delete $glb_childs{ $task->pid() }; 
    }
}
    
sub pipe_local_read {
    my ( $pipe, $timeout ) = @_;
    my $rbuf = undef;
    my $r_st = undef;

    vec($r_st, fileno($pipe),  1) = 1;
    if(select($r_st, undef, undef, $timeout)) {
      my $rv = sysread($pipe, $rbuf, 4);
      if($rv ne 4) { return undef; }

      my $len = unpack("I", $rbuf);
      if($len <= 0) { return undef; }

      sysread($pipe, $rbuf, $len);
    }
    return $rbuf;
}

sub pipe_local_write {
    my ($pipe, $timeout, $data) = @_;
    unless(defined $data) { 
      return undef;
    }
    my $w_st = undef;
    
    vec($w_st, fileno($pipe),  1) = 1;
    if(select(undef, $w_st, undef, $timeout)) {
      my $data_size = pack("I", length($data));
      my $buf_out = $data_size.$data;
      syswrite($pipe, $buf_out, length($buf_out));
      return 1;
    }    
    return undef;
}

# ---------------------------------------------------------------------------------------------------------------------------------------------------------------
{
  package XSpawn::Task;
  
  use POSIX;
  use overload 
    '""'     => sub { $_[0]->to_string };
  
  sub new ($$) {
    my($class, $node_id) = @_;
    my $self = {
      class           => $class,
      id              => undef,
      pid             => undef,
      node            => $node_id,
      lr_timeout      => 0.1,
      lw_timeout      => 0.1,
      c_pipe_w        => undef,
      c_pipe_r        => undef,
      p_pipe_w        => undef,
      p_pipe_r        => undef,
      fl_parent       => 0,
      fl_interrupted  => 0,
      fl_destroyed    => 0,
    };
    bless($self, $class);
    return $self;
  }
   
  sub get_class_name {
    my ($self) = @_;
    return $self->{class};
  }
  
  sub to_string {
    my($self) = @_;
    return 'Task: ' .$self->{id}. " (" . $self->{node}." / ".$self->{pid}." / ".($self->{fl_parent} ? 'P' : "C").")";
  }

  sub id {
    my ($self, $val) = @_;
    return $self->{id};
  }

  sub pid {
    my ($self, $val) = @_;
    return $self->{pid} + 0 unless(defined $val);
    $self->{pid} = $val + 0 unless(defined $self->{pid});
  }

  sub node {
    my ($self, $val) = @_;
    return $self->{node} unless(defined $val);
    $self->{node} = $val unless(defined $self->{node});
  }

  sub is_interruped {
    my ($self) = @_;
    return $self->{fl_interrupted};
  }

  sub is_destroyed {
    my ($self) = @_;
    return $self->{fl_destroyed};
  }

  sub is_local {
    my ($self) = @_;
    return 1;
  }
  
  sub message_read {
    my ($self) = @_;
    my $buff = undef;
    
    if($self->{fl_parent}) {
	$buff = XSpawn::pipe_local_read($self->{p_pipe_r}, $self->{lr_timeout});
    } else {
	$buff = XSpawn::pipe_local_read($self->{c_pipe_r}, $self->{lr_timeout});
    }      
    return $buff;
  }
  
  sub message_write {
    my ($self, $msg) = @_;
    my $rc = undef;
    
    if($self->{fl_parent}) {
        $rc = XSpawn::pipe_local_write($self->{c_pipe_w}, $self->{lw_timeout}, $msg);
    } else {
        $rc = XSpawn::pipe_local_write($self->{p_pipe_w}, $self->{lw_timeout}, $msg);
    }      
    return $rc;
  }

  sub cleanup {
    my ($self) = @_;
    $self->{fl_destroyed} = 1;
    close($self->{c_pipe_r});
    close($self->{c_pipe_w});
    close($self->{p_pipe_r});
    close($self->{p_pipe_w});
  }

  sub interrupt {
    my ($self) = @_;
    kill('INT', $self->{pid});
  }
  
  sub terminate {
    my ($self) = @_;
    kill('TERM', $self->{pid});
  }

  sub do_fork {
    my ($self) = @_;

    pipe($self->{c_pipe_r}, $self->{c_pipe_w});
    pipe($self->{p_pipe_r}, $self->{p_pipe_w});
    $self->{c_pipe_w}->autoflush(1);      
    $self->{p_pipe_w}->autoflush(1);      
    
    fcntl($self->{c_pipe_r}, F_SETFL, fcntl($self->{c_pipe_r}, F_GETFL, 0) | O_NONBLOCK);
    fcntl($self->{p_pipe_r}, F_SETFL, fcntl($self->{p_pipe_r}, F_GETFL, 0) | O_NONBLOCK);
    
    $self->{pid} = fork();
    $self->{id} = $self->{pid};
    unless(defined $self->{pid}) { 
      $self->cleanup();
      die "Fork faild";
    }    
    
    if($self->{pid} == 0) {
      $SIG{INT}  = sub { $self->{fl_interrupted} = 1;  };
      $SIG{TERM} = sub { exit(0);  };
      $SIG{CHLD} = undef;
      $self->{fl_parent} = 0;
      $self->{pid} = $$;
      $self->{id} = $self->{pid};
      close($self->{c_pipe_w});
      close($self->{p_pipe_r});
      return 1;
    }    
    
    $self->{fl_parent} = 1;
    close($self->{c_pipe_r});
    close($self->{p_pipe_w});
    return 0;
  }  
}

1;
