#!/usr/bin/perl
# extract_cmd_output.pl — Extract command stdout/stderr from serial_terminal logs.
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

my $log_file = shift @ARGV or do { print_usage(); exit 1 };
my $regex    = shift @ARGV or do { print_usage(); exit 1 };

die "Error: File '$log_file' not found.\n" unless -f $log_file;

my @commands = extract_commands($log_file, $regex);

if ($json_output) {
    print JSON::PP->new->pretty->canonical->encode({commands => \@commands});
} elsif (!@commands) {
    print "No commands matching '$regex' found in $log_file\n";
}

=head2 extract_commands($file, $regex_str)

Extracts command outputs from a serial_terminal log file. Matches command
lines of the form C<# cmd; echo TAG-$?-> and captures everything until
the end tag C<TAG-exitcode->.

Returns a list of hashrefs with keys: command, output, exit_code, tag.

=cut

sub extract_commands {
    my ($file, $regex_str) = @_;
    my @results;

    my $in_command = 0;
    my $tag        = '';
    my $full_cmd   = '';
    my @output_buf;

    open my $fh, '<', $file or die "Cannot open '$file': $!\n";
    while (my $line = <$fh>) {
        chomp $line;
        $line =~ s/\r//g;

        # Match command start: line starts with #, matches regex, has echo tag pattern
        if ($line =~ /^# / && $line =~ /$regex_str/ && $line =~ /; echo ([^\s]+)-\$\?-/) {
            my $new_tag = $1;

            # Finalize previous command if still open
            if ($in_command && @output_buf) {
                push @results, _build_result($full_cmd, \@output_buf, 'unknown', $tag);
            }

            # Extract full command
            ($full_cmd = $line) =~ s/^# //;
            $tag        = $new_tag;
            @output_buf = ();
            $in_command = 1;

            unless ($json_output) {
                my $sep    = '=' x 80;
                my $header = "COMMAND: $full_cmd";
                if ($use_color) {
                    print colored($sep, 'cyan'), "\n";
                    print colored($header, 'bold'), "\n";
                    print colored($sep, 'cyan'), "\n";
                } else {
                    print "\n$sep\n$header\n$sep\n";
                }
            }
            next;
        }

        # Capture output lines
        if ($in_command) {
            # Check for end tag: TAG-<exit_code>-
            if ($line =~ /^\Q$tag\E-(\d+)-/) {
                my $exit_code = $1;
                push @results, _build_result($full_cmd, \@output_buf, $exit_code, $tag);

                unless ($json_output) {
                    my $divider = '-' x 80;
                    my $result  = "RESULT: $line";
                    if ($use_color) {
                        print colored($divider, 'cyan'), "\n";
                        my $rc_color = ($exit_code eq '0') ? 'green' : 'red';
                        print colored($result, $rc_color), "\n";
                    } else {
                        print "$divider\n$result\n";
                    }
                }

                $in_command = 0;
                $tag        = '';
                @output_buf = ();
            } else {
                push @output_buf, $line;
                print "$line\n" unless $json_output;
            }
        }
    }
    close $fh;

    # Handle unterminated command
    if ($in_command && @output_buf) {
        push @results, _build_result($full_cmd, \@output_buf, 'unknown', $tag);
    }

    return @results;
}

sub _build_result {
    my ($cmd, $output_ref, $exit_code, $tag) = @_;
    return {
        command   => $cmd,
        output    => join("\n", @$output_ref),
        exit_code => $exit_code,
        tag       => $tag,
    };
}

sub print_usage {
    print <<'USAGE';
Usage: extract_cmd_output.pl [OPTIONS] <serial_terminal_log> <regex>

Extract command stdout/stderr from openQA serial_terminal.txt logs.
Matches commands by the given regex and displays their full output
including the exit code.

NOTE: This tool operates on serial_terminal.txt, not autoinst-log.txt.

Arguments:
  serial_terminal_log   Path to serial_terminal.txt log file
  regex                 Regex pattern to match commands

Options:
  --json            Output results as JSON
  --color           Enable colored output
  --verbose         Print progress messages
  --help, -h        Show this help

Examples:
  extract_cmd_output.pl serial_terminal.txt "zypper"
  extract_cmd_output.pl serial_terminal.txt "az vm create"
  extract_cmd_output.pl --json serial_terminal.txt "crm configure"
USAGE
}
