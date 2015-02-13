#!/bin/env perl
use strict;
use warnings;
use 5.010;
use Getopt::Long qw(:config posix_default no_ignore_case gnu_compat);
use Pod::Usage;
use Time::Piece;
use utf8;
use IO::Dir;
use Mail::Sendmail;
use Encode ();

my $path_conf   = '/your/conf/dir/rej.conf';

GetOptions(\my %opt, qw/
    conf=s
    dir=s
    key|k=s
    command|c=s
    info|i
    clear=s
    help|h|usage|u
/) or pod2usage({ -verbose => 2, -output  => \*STDERR });

pod2usage({ -verbose => 2, -output  => \*STDERR }) if (exists $opt{help} || exists $opt{h} || exists $opt{usage} || exists $opt{u});

$opt{conf}      //= $path_conf;
$opt{key}       //= $opt{k} // '';
$opt{command}   //= $opt{c};

die "conf path not found. : " . $opt{conf} if (!-f $opt{conf});

my $conf            = require $opt{conf};

$opt{dir}       //= $conf->{log}{dir};

die "log dir not found. : " . $opt{dir} if (!-d $opt{dir});

$opt{path_abend}    = $opt{dir} . '/aben_' . $opt{key} . '.abe';
$opt{path_lock}     = $opt{dir} . '/lock_' . $opt{key} . '.lck';
$opt{path_hist}     = $opt{dir} . '/hist_' . $opt{key} . '.txt';
$opt{status}        = 'exit_halfway';

my $node_name       = do {
    open(my $ph, '-|', "uname -n") or die "uname -n";
    my $nn  = <$ph>;
    chomp $nn;
    close($ph);
    $nn;
};

# clear system files
if ($opt{clear}) {
    my $regexp  = '^' . $opt{clear} . '_' . (($opt{key}) ? $opt{key} : '.*');
    tie my %dir, 'IO::Dir', $opt{dir};
    for my $name (keys %dir) {
        next if ($name !~ m/$regexp/);
        my $path    = $opt{dir} . '/' . $name;
        if (unlink($path) <= 0) {
            say "error unlink " . $path;
        }
    }
}
#
elsif (exists $opt{info} || exists $opt{i}) {
    print_summary();
}
# history
elsif ($opt{key} && ! $opt{command}) {
    if (-f $opt{path_hist}) {
        open(my $fh, '<', $opt{path_hist});
        while (<$fh>) {
            print $_;
        }
        close($fh);
    }
}
# execute command
elsif ($opt{key} && $opt{command}) {
    execute_command();
}
# 
else {
    pod2usage({ -verbose => 2, -output  => \*STDERR });
}

exit 0;

# 
sub execute_command {
    $SIG{'INT'}		= \&end_processing;
    $SIG{'QUIT'}	= \&end_processing;
    $SIG{'TERM'}	= \&end_processing;
    
    my $t           = localtime;
    $opt{now}       = $t->ymd . ' ' . $t->hms;
    
    if (-f $opt{path_lock}) {
        my $message = sprintf("rej : %s : %s\n", $opt{now}, $opt{command});
        print $message;
        add_text($opt{path_hist}, $message);
        exit 0;
    }

    create_text($opt{path_lock}, 'w');
    add_text($opt{path_hist}, sprintf("\nin  : %s : %s\n", $opt{now}, $opt{command}));
    
    $opt{status}    = system($opt{command});
    $t              = localtime;
    $opt{now}       = $t->ymd . ' ' . $t->hms;
    
    end_processing();
}

#
sub create_text {
    open(my $fh, '>', $_[0]) || die "error create_text open " . $_[0];
    print $fh $_[1];
    close($fh);
}

#
sub add_text {
    open(my $fh, '>>', $_[0]) || die "error add_text open " . $_[0];
    print $fh $_[1];
    close($fh);
}

#
sub end_processing {
    if ($opt{status} eq 'exit_halfway') {
        say "exit_halfway : " . $opt{path_lock};
    }
    if (-f $opt{path_lock}) {
        if (unlink($opt{path_lock}) <= 0) {
            say "error unlink " . $opt{path_lock};
        }
    }
    add_text($opt{path_hist}, sprintf("out : %s : %s (%s)\n", $opt{now}, $opt{command}, $opt{status}));
    
    # abnormal end
    if ($opt{status} != 0) {
        if (!-f $opt{path_abend}) {
            create_text($opt{path_abend}, 'w');
            add_text($opt{path_hist}, sprintf("inf : %s : AbEnd alarm !!!\n", $opt{now}));
            
            # create mail
            if ($conf->{mail}{send} && $conf->{mail}{from} && $conf->{mail}{to}) {
                my $subject         = ($conf->{mail}{subject}) ? $conf->{mail}{subject} . ' : ' : '';
                $subject            .= "rej AbEnd ! : [" . $opt{key} . "] " . $node_name . " - " . $opt{now};
                my $hist_log_size   = $conf->{mail}{hist_log_size} || 100;
                my $body            = "abnormal end alarm. key = [" . $opt{key} . "] server = [" . $node_name . "]\n\n";
                $body               = "> tail -${hist_log_size} " . $opt{path_hist} . "\n";
                open(my $fh, "tail -${hist_log_size} " . $opt{path_hist} . " |");
                while (<$fh>) {
                    $body   .= $_;
                }
                close($fh);
                my %mail    = (
                    'Content-Type'  => 'text/plain; charset="iso-2022-jp"',
                    From            => $conf->{mail}{from},
                    To              => $conf->{mail}{to},
                    Subject         => Encode::encode('MIME-Header-ISO_2022_JP', $subject),
                    message         => Encode::encode('iso-2022-jp', $body),
                );
                sendmail(%mail) or die $Mail::Sendmail::error;
                say "send mail : ${subject}";
            }
        }
    }
    else {
        if (-f $opt{path_abend}) {
            if (unlink($opt{path_abend}) <= 0) {
                say "error unlink " . $opt{path_abend};
            }
            add_text($opt{path_hist}, sprintf("inf : %s : AbEnd clear ...\n", $opt{now}));
        }
    }
    exit 0;
}

#
sub print_summary {
    my @a_path  = ();
    tie my %dir, 'IO::Dir', $opt{dir};
    for my $name (keys %dir) {
        next if ($name !~ m/^hist_.+\.txt$/);
        push @a_path, $opt{dir} . '/' . $name;
    }
    print "\n";
    print sprintf(" %-20s %-3s %-3s %-19s %-19s %-7s %-7s\n", "key", "lck", "AbE", "last-in", "last-out", "out-cnt", "rej-cnt");
    foreach my $path (sort @a_path) {
        if ($path !~ m{hist_([^/]+)\.txt$}) { die "error print_summary"; }
        my $key         = $1;
        my $lck         = (-f $opt{dir} . '/lock_' . $key . '.lck') ? 'lck' : '   ';
        my $abe         = (-f $opt{dir} . '/aben_' . $key . '.abe') ? 'abe' : '   ';
        my $cnt_out     = 0;
        my $cnt_rej     = 0;
        my $last_in     = '';
        my $last_out    = '';
        open (my $fh, $path) or die "error open ${path}";
        while (<$fh>) {
            if (m/^rej : /) {
                $cnt_rej ++;
            }
            elsif (m/^in  : (.+) : /) {
                $last_in    = $1;
                $last_out   = '';
            }
            elsif (m/^out : (.+) : /) {
                $last_out   = $1;
                $cnt_out ++;
            }
        }
        close($fh);
        print sprintf(" %-20s %3s %-3s %19s %19s %7d %7d\n", $key, $lck, $abe, $last_in, $last_out, $cnt_out, $cnt_rej);
    }
    print "\n";
}

__END__

=encoding utf8

=head1 NAME

rej.pl

=head1 SYNOPSIS

=over 4

=item * rej.pl -k <key> -c <command>                : 多重起動防止で command 実行

=item * rej.pl -i                                   : 一覧表示

=item * rej.pl -k <key>                             : 履歴表示

=item * rej.pl --clear (aben|lock|hist) [-k <key>]  : システムファイル削除

=back

多重起動防止。rej.pl 経由でコマンドを実行（実行形式である必要がある）。
別のコマンドであろうが、rej.pl は key に対して１つしか起動できない。

コマンドの実行履歴を確認することが出来る。

config に設定すれば、AbEnd（abnormal end）時にメールを送信することが出来る。
連続して AbEnd した場合、メール送信するのは初回のみ。

=cut
