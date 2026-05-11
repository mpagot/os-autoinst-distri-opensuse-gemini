#!/usr/bin/perl
# analyze_log_health.pl — Analyze openQA log files to identify critical issues.
# Detects test failures, timeouts, hook errors, backend stress, ring buffer
# overflows, PIPE_SZ changes, and extracts Perl backtraces.
# Run with --help for full usage information.

use strict;
use warnings;
use Getopt::Long;
use JSON::PP;
use Term::ANSIColor qw(colored);

my $verbose        = 0;
my $json_output    = 0;
my $use_color      = 0;
my $loop_threshold = 100_000;
my $help           = 0;

GetOptions(
    'verbose'          => \$verbose,
    'json'             => \$json_output,
    'color'            => \$use_color,
    'loop-threshold=i' => \$loop_threshold,
    'help|h'           => \$help,
) or do { print_usage(); exit 1 };

if ($help) { print_usage(); exit 0 }

my @log_files = @ARGV;
die "Usage: $0 [OPTIONS] <log_file> [log_file2 ...]\nTry --help for details.\n" unless @log_files;

for my $log_file (@log_files) {
    analyze_file($log_file);
}

=head2 analyze_file($file)

Parses a single openQA autoinst-log file and reports all detected issues.
In text mode, issues are printed inline as encountered. In JSON mode, all
issues are collected and output as a single JSON document per file.

=cut

sub analyze_file {
    my ($file) = @_;
    die "File not found: $file\n" unless -f $file;

    unless ($json_output) {
        my $sep = '=' x 80;
        print_colored("$sep\n", 'bold');
        print_colored("Analyzing: $file\n", 'bold');
        print_colored("$sep\n", 'bold');
    }

    my $current_module = 'Unknown';
    my $in_backtrace   = 0;
    my @current_bt;
    my @issues;
    my %summary = (errors => 0, warnings => 0, info => 0);

    open my $fh, '<', $file or die "Cannot open '$file': $!\n";
    while (my $line = <$fh>) {
        chomp $line;

        # Track module context
        if ($line =~ /\|\|\| starting\s+(\S+)/) {
            $current_module = $1;
        }

        # Backtrace continuation (checked early, before other patterns)
        if ($in_backtrace) {
            if ($line =~ /^\[\d{4}-/ || $line =~ /^\s*$/) {
                # End of backtrace — attach to last issue
                _finalize_backtrace(\@issues, \@current_bt);
                $in_backtrace = 0;
                # Fall through to check patterns on this line
            } else {
                (my $bt_line = $line) =~ s/^\s+//;
                push @current_bt, $bt_line;
                unless ($json_output) {
                    print_colored("  at $bt_line\n", 'yellow');
                }
                next;
            }
        }

        # Test died / timed out — starts new backtrace
        if ($line =~ /Test died|timed out/) {
            my $ts  = extract_ts($line);
            my $msg = extract_error_message($line);
            push @issues, {
                type      => 'error',
                module    => $current_module,
                message   => $msg,
                timestamp => $ts,
                backtrace => [],
            };
            $in_backtrace = 1;
            $summary{errors}++;

            unless ($json_output) {
                print_colored("ERROR in $current_module: $msg (at $ts)\n", 'bold red');
            }
            next;
        }

        # Hook failures
        if ($line =~ /!!! (.*)/) {
            my $msg = $1;
            my $ts  = extract_ts($line);
            push @issues, {
                type      => 'hook_error',
                module    => $current_module,
                message   => $msg,
                timestamp => $ts,
            };
            $summary{errors}++;

            unless ($json_output) {
                print_colored("HOOK ERROR in $current_module: $msg (at $ts)\n", 'red');
            }
            next;
        }

        # Explicit fail results
        if ($line =~ />>> (.*: fail.*)/) {
            my $res = $1;
            my $ts  = extract_ts($line);
            push @issues, {
                type      => 'fail_result',
                module    => $current_module,
                message   => $res,
                timestamp => $ts,
            };
            $summary{errors}++;

            unless ($json_output) {
                print_colored("RESULT in $current_module: $res (at $ts)\n", 'red');
            }
            next;
        }

        # Backend stress (high loop counts)
        if ($line =~ /Matched output from SUT/ && $line =~ /in (\d+) loops/) {
            my $loops = $1 + 0;
            if ($loops > $loop_threshold) {
                my $ts = extract_ts($line);
                push @issues, {
                    type      => 'heavy_load',
                    module    => $current_module,
                    loops     => $loops,
                    timestamp => $ts,
                };
                $summary{warnings}++;

                unless ($json_output) {
                    print_colored("HEAVY LOAD in $current_module: $loops loops detected during match (at $ts)\n", 'yellow');
                }
            }
        }

        # Ring buffer overflow
        if ($line =~ /(Ring buffer overflow: .*)/) {
            my $msg = $1;
            my $ts  = extract_ts($line);
            push @issues, {
                type      => 'ring_buffer',
                module    => $current_module,
                message   => $msg,
                timestamp => $ts,
            };
            $summary{warnings}++;

            unless ($json_output) {
                print_colored("WARNING in $current_module: $msg (at $ts)\n", 'yellow');
            }
        }

        # PIPE_SZ changes
        if ($line =~ /(Set PIPE_SZ .*)/) {
            my $msg = $1;
            my $ts  = extract_ts($line);
            push @issues, {
                type      => 'pipe_sz',
                module    => $current_module,
                message   => $msg,
                timestamp => $ts,
            };
            $summary{info}++;

            unless ($json_output) {
                print_colored("INFO in $current_module: $msg (at $ts)\n", 'cyan');
            }
        }
    }
    close $fh;

    # Finalize any pending backtrace
    if ($in_backtrace) {
        _finalize_backtrace(\@issues, \@current_bt);
    }

    # Output
    if ($json_output) {
        print JSON::PP->new->pretty->canonical->encode({
            file    => $file,
            issues  => \@issues,
            summary => \%summary,
        });
    } else {
        print "\n";
        if ($summary{errors} == 0) {
            print_colored("No critical errors detected, but check warnings for load issues.\n", 'cyan');
        } else {
            print_colored("Total critical issues detected: $summary{errors}\n", 'bold red');
        }
        print "\n";
    }
}

=head2 extract_ts($line)

Extracts the timestamp from the leading C<[timestamp]> bracket in a log line.
Returns C<'unknown'> if no timestamp is found.

=cut

sub extract_ts {
    my ($line) = @_;
    return ($line =~ /^\[([^\]]+)\]/) ? $1 : 'unknown';
}

=head2 extract_error_message($line)

Extracts the error message from a C<Test died> or C<timed out> log line.
Looks for the C<::: > prefix and strips the C<basetest::runtest: # > leader.

=cut

sub extract_error_message {
    my ($line) = @_;
    my $msg;
    if ($line =~ /::: (.*)/) {
        $msg = $1;
    } else {
        $msg = $line;
    }
    $msg =~ s/^basetest::runtest: # //;
    return $msg;
}

=head2 print_colored($text, $color_spec)

Prints text with optional ANSI color. Only applies color when C<--color>
is active.

=cut

sub print_colored {
    my ($text, $color_spec) = @_;
    print $use_color ? colored($text, $color_spec) : $text;
}

sub _finalize_backtrace {
    my ($issues_ref, $bt_ref) = @_;
    if (@$bt_ref && @$issues_ref) {
        $issues_ref->[-1]{backtrace} = [@$bt_ref];
    }
    @$bt_ref = ();
}

sub print_usage {
    print <<'USAGE';
Usage: analyze_log_health.pl [OPTIONS] <log_file> [log_file2 ...]

Analyze openQA autoinst-log files to identify critical issues including
test failures, timeouts, hook errors, backend stress, and more.

Options:
  --json              Output results as JSON
  --color             Enable colored output
  --verbose           Print progress messages
  --loop-threshold N  Loop count threshold for heavy load warnings
                      (default: 100000)
  --help, -h          Show this help

Detected issue types:
  ERROR       Test died / timed out (with Perl backtrace extraction)
  HOOK ERROR  Hook failures (!!! markers)
  RESULT      Explicit fail results (>>> markers)
  HEAVY LOAD  Backend stress (high loop counts in serial matching)
  WARNING     Ring buffer overflows
  INFO        PIPE_SZ changes

Examples:
  analyze_log_health.pl autoinst-log.txt
  analyze_log_health.pl --color autoinst-log.txt
  analyze_log_health.pl --json --loop-threshold 50000 autoinst-log.txt
  analyze_log_health.pl log1.txt log2.txt log3.txt
USAGE
}
