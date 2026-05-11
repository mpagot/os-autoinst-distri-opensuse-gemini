#!/usr/bin/perl
# compare_modules_time.pl — Compare time distribution across test modules between logs.
# Run with --help for full usage information.

use strict;
use warnings;
use Getopt::Long;
use JSON::PP;
use Term::ANSIColor qw(colored);
use Time::Local qw(timelocal);

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
die "Usage: $0 [OPTIONS] <log1> <log2> [log3 ...]\nTry --help for details.\n" unless @log_files >= 1;

# Gather stats from all logs
my %all_data;
my %all_modules;

for my $log (@log_files) {
    die "File not found: $log\n" unless -f $log;
    my $data = get_module_stats($log);
    $all_data{$log} = $data;
    $all_modules{$_} = 1 for keys %$data;
}

my @sorted_modules = sort keys %all_modules;

# Output
if ($json_output) {
    my %modules_json;
    for my $mod (@sorted_modules) {
        for my $log (@log_files) {
            my $stats = $all_data{$log}{$mod} // {wall => 0, cmd => 0, overhead => 0};
            $modules_json{$mod}{$log} = $stats;
        }
    }
    print JSON::PP->new->pretty->canonical->encode({
        logs    => \@log_files,
        modules => \%modules_json,
    });
} else {
    print_table(\@log_files, \@sorted_modules, \%all_data);
}

=head2 parse_ts($ts_str)

Parses an openQA timestamp string (ISO 8601) into epoch seconds with
fractional precision. Strips timezone offset for local time comparison.

=cut

sub parse_ts {
    my ($ts_str) = @_;
    # Strip timezone offset (+HH:MM or Z)
    $ts_str =~ s/[+-]\d{2}:\d{2}$//;
    $ts_str =~ s/Z$//;
    if ($ts_str =~ /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?$/) {
        my ($y, $mo, $d, $h, $mi, $s) = ($1, $2, $3, $4, $5, $6);
        my $frac = defined $7 ? "0.$7" + 0 : 0;
        my $epoch = eval { timelocal($s, $mi, $h, $d, $mo - 1, $y) };
        return 0 if $@;
        return $epoch + $frac;
    }
    return 0;
}

=head2 get_module_stats($file_path)

Parses an autoinst-log file and computes per-module timing statistics:

=over

=item * B<wall> — Wall-clock time (timestamp delta between module transitions)

=item * B<cmd> — Sum of command execution durations within the module

=item * B<overhead> — Framework overhead (wall - cmd)

=back

Returns a hashref of C<< module_name => {wall, cmd, overhead} >>.

=cut

sub get_module_stats {
    my ($file_path) = @_;

    my %stats;
    my $current_module  = undef;
    my $module_start_ts = 0;
    my $command_time    = 0;
    my $last_ts         = 0;

    open my $fh, '<', $file_path or die "Cannot open '$file_path': $!\n";
    while (my $line = <$fh>) {
        chomp $line;

        # Extract timestamp from any log line
        if ($line =~ /\[(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[^\]]*)\]/) {
            $last_ts = parse_ts($1);
        }

        # Track module transitions
        if ($line =~ /\|\|\| starting\s+(\S+)\s+tests\//) {
            my $module_name = $1;
            my $ts = 0;
            if ($line =~ /^\[([^\]]+)\]/) {
                $ts = parse_ts($1);
            }

            # Finalize previous module
            if (defined $current_module && $ts > 0 && $module_start_ts > 0) {
                my $wall = $ts - $module_start_ts;
                $stats{$current_module} = {
                    wall     => $wall,
                    cmd      => $command_time,
                    overhead => ($wall > $command_time) ? $wall - $command_time : 0,
                };
                warn "Module $current_module: wall=$wall cmd=$command_time overhead=" . ($wall - $command_time) . "\n"
                    if $verbose;
            }

            $current_module  = $module_name;
            $module_start_ts = $ts;
            $command_time    = 0;
            next;
        }

        # Track command durations
        if ($line =~ /Matched output from SUT in .* & ([\d.]+) seconds/) {
            $command_time += $1 + 0 if defined $current_module;
        }
    }
    close $fh;

    # Handle the last module
    if (defined $current_module && $last_ts > 0 && $module_start_ts > 0) {
        my $wall = $last_ts - $module_start_ts;
        $stats{$current_module} = {
            wall     => $wall,
            cmd      => $command_time,
            overhead => ($wall > $command_time) ? $wall - $command_time : 0,
        };
    }

    return \%stats;
}

=head2 print_table($log_files, $modules, $all_data)

Prints a side-by-side comparison table of module timing across log files.

=cut

sub print_table {
    my ($logs_ref, $mods_ref, $data_ref) = @_;

    # Build header
    my $header = sprintf("%-25s", 'Module Name');
    for my $log (@$logs_ref) {
        my $short = short_name($log);
        $header .= sprintf(" | %18s", $short);
    }

    my $divider = '-' x length($header);
    my $sub_header = sprintf("%-25s", '');
    for my $i (0 .. $#$logs_ref) {
        $sub_header .= ' |  Wall   Cmd  Over ';
    }

    if ($use_color) {
        print colored($header, 'bold'), "\n";
        print colored($divider, 'cyan'), "\n";
        print colored($sub_header, 'bold'), "\n";
        print colored($divider, 'cyan'), "\n";
    } else {
        print "$header\n$divider\n$sub_header\n$divider\n";
    }

    # Print rows
    for my $mod (@$mods_ref) {
        my $row = sprintf("%-25s", substr($mod, 0, 25));
        my $max_overhead = 0;

        # Pre-calculate max overhead for color highlighting
        if ($use_color) {
            for my $log (@$logs_ref) {
                my $s = $data_ref->{$log}{$mod} // {overhead => 0};
                $max_overhead = $s->{overhead} if $s->{overhead} > $max_overhead;
            }
        }

        for my $log (@$logs_ref) {
            my $s = $data_ref->{$log}{$mod} // {wall => 0, cmd => 0, overhead => 0};
            $row .= sprintf(" | %5.0f %5.0f %5.0f", $s->{wall}, $s->{cmd}, $s->{overhead});
        }

        if ($use_color && $max_overhead > 60) {
            print colored($row, 'yellow');
        } else {
            print $row;
        }
        print "\n";
    }
}

=head2 short_name($log_path)

Extracts a short display name from a log file path for table headers.

=cut

sub short_name {
    my ($log) = @_;
    # Try to extract a meaningful short name from the file path
    if ($log =~ /([^\/]+)\.txt$/) {
        my $name = $1;
        return length($name) > 18 ? substr($name, 0, 15) . '...' : $name;
    }
    return length($log) > 18 ? substr($log, 0, 15) . '...' : $log;
}

sub print_usage {
    print <<'USAGE';
Usage: compare_modules_time.pl [OPTIONS] <log1> <log2> [log3 ...]

Compare wall-clock time, command time, and overhead across test modules
between multiple openQA autoinst-log files. Useful for identifying
regressions or locating where framework overhead increased.

Timing definitions:
  Wall      Timestamp delta between module start markers
  Cmd       Sum of "Matched output from SUT" durations in the module
  Overhead  Wall - Cmd (framework time: needle matching, etc.)

Options:
  --json            Output results as JSON
  --color           Enable colored output (highlights high overhead)
  --verbose         Print per-module debug info
  --help, -h        Show this help

Examples:
  compare_modules_time.pl pass_log.txt fail_log.txt
  compare_modules_time.pl --json log1.txt log2.txt log3.txt
  compare_modules_time.pl --color old_run.txt new_run.txt
USAGE
}
