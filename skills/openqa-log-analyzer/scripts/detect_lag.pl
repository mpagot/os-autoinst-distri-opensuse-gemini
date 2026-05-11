#!/usr/bin/perl
# detect_lag.pl — Detect backend performance issues by correlating loop counts with timeouts.
# Helps determine if a failure was caused by SUT slowness or backend/host stress.
# Run with --help for full usage information.

use strict;
use warnings;
use Getopt::Long;
use JSON::PP;
use Term::ANSIColor qw(colored);

my $verbose     = 0;
my $json_output = 0;
my $use_color   = 0;
my $help        = 0;

GetOptions(
    'verbose' => \$verbose,
    'json'    => \$json_output,
    'color'   => \$use_color,
    'help|h'  => \$help,
) or do { print_usage(); exit 1 };

if ($help) { print_usage(); exit 0 }

my @log_files = @ARGV;
die "Usage: $0 [OPTIONS] <log_file> [log_file2 ...]\nTry --help for details.\n" unless @log_files;

my @all_timeouts;

unless ($json_output) {
    my $header = sprintf("%-30s %-10s %-10s %-30s %s", 'Log File', 'Max Loops', 'Max Dur', 'Longest CMD', 'Failed CMD');
    if ($use_color) {
        print colored($header, 'bold'), "\n";
    } else {
        print "$header\n";
    }
    print '-' x 112, "\n";
}

for my $log_file (@log_files) {
    unless (-f $log_file) {
        warn "File not found: $log_file\n" if $verbose;
        next;
    }
    my @timeouts = detect_lag($log_file);
    push @all_timeouts, @timeouts;
}

if ($json_output) {
    print JSON::PP->new->pretty->canonical->encode({timeouts => \@all_timeouts});
}

=head2 detect_lag($file)

Scans a log file for C<Matched output from SUT> lines, tracking the maximum
loop count and duration. When a C<Test died: command ... timed out> line is
found, emits a lag report and resets counters.

Returns a list of timeout result hashrefs.

=cut

sub detect_lag {
    my ($file) = @_;
    my @timeouts;

    my $max_loops   = 0;
    my $max_dur     = 0;
    my $longest_cmd = 'None';

    open my $fh, '<', $file or die "Cannot open '$file': $!\n";
    while (my $line = <$fh>) {
        chomp $line;

        # Track maximum loops and duration from serial matching
        if ($line =~ /Matched output from SUT/) {
            if ($line =~ /in (\d+) loops/) {
                my $loops = $1 + 0;
                if ($line =~ /& ([\d.]+) seconds/) {
                    my $dur = $1 + 0;
                    if ($loops > $max_loops) {
                        $max_loops = $loops;
                        $max_dur   = $dur;
                        if ($line =~ /seconds: (.*)/) {
                            $longest_cmd = $1;
                            $longest_cmd = substr($longest_cmd, 0, 27) . '...'
                                if length($longest_cmd) > 30;
                        }
                    }
                }
            }
        }

        # Timeout event — emit lag report and reset
        if ($line =~ /Test died: command .* timed out/) {
            my $failed_cmd = 'unknown';
            if ($line =~ /(command \S*)/) {
                $failed_cmd = $1;
            }

            my $result = {
                file         => $file,
                max_loops    => $max_loops,
                max_duration => $max_dur + 0.0,
                longest_cmd  => $longest_cmd,
                failed_cmd   => $failed_cmd,
            };
            push @timeouts, $result;

            unless ($json_output) {
                my $text = sprintf("%-30s %-10d %-10.2f %-30s %s",
                    $file, $max_loops, $max_dur, $longest_cmd, $failed_cmd);
                if ($use_color && $max_loops > 100_000) {
                    print colored($text, 'yellow');
                } else {
                    print $text;
                }
                print "\n";
            }

            warn "Timeout: max_loops=$max_loops max_dur=$max_dur failed=$failed_cmd\n" if $verbose;

            # Reset counters for next section
            $max_loops   = 0;
            $max_dur     = 0;
            $longest_cmd = 'None';
        }
    }
    close $fh;

    return @timeouts;
}

sub print_usage {
    print <<'USAGE';
Usage: detect_lag.pl [OPTIONS] <log_file> [log_file2 ...]

Detect backend performance issues by correlating high loop counts with
command timeouts in openQA autoinst-log files. High loop counts indicate
the os-autoinst backend was under stress (CPU contention, I/O wait),
suggesting the timeout was caused by host overload rather than SUT failure.

Options:
  --json            Output results as JSON
  --color           Enable colored output (highlights high loop counts)
  --verbose         Print progress messages
  --help, -h        Show this help

Output columns:
  Log File      Path to the analyzed log file
  Max Loops     Maximum loop count seen before the timeout
  Max Dur       Maximum duration (seconds) of the longest match
  Longest CMD   The command that took the most loops to match
  Failed CMD    The command that ultimately timed out

Examples:
  detect_lag.pl autoinst-log.txt
  detect_lag.pl --json autoinst-log.txt
  detect_lag.pl --color log1.txt log2.txt log3.txt
USAGE
}
