#!/usr/bin/env bash
# macOS Bash 3.2 / Linux. Uses curl and Perl; no browser or Node.js.
set -euo pipefail
script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
export SOURCE_URL='https://www.cisco.com/c/en/us/td/docs/security/vpn_client/anyconnect/Cisco-Secure-Client-5/release/notes/release-notes-cisco-secure-client-5-1.html'
export HISTORY_FILE="${HISTORY_FILE:-$script_dir/data/anyconnect-history.csv}"
export LATEST_FILE="${LATEST_FILE:-$(dirname -- "$HISTORY_FILE")/anyconnect-latest.json}"
for tool in curl perl; do
  command -v "$tool" >/dev/null || { echo "Missing required tool: $tool" >&2; exit 1; }
done
task_tmp="$(mktemp -d)"
trap 'rm -rf "$task_tmp"' EXIT
if [[ -n "${NOTES_FILE:-}" ]]; then
  cp "$NOTES_FILE" "$task_tmp/notes.html"
else
  curl --fail --location --silent --show-error --retry 2 \
    --connect-timeout 15 --max-time 90 "$SOURCE_URL" -o "$task_tmp/notes.html"
fi
perl - "$task_tmp/notes.html" <<'PERL'
use strict;
use warnings;
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Temp qw(tempfile);
use POSIX qw(strftime);
use JSON::PP;
sub clean {
  my ($s)=@_; $s =~ s/<[^>]*>/ /gs; $s =~ s/&nbsp;|&#160;/ /g;
  $s =~ s/\s+/ /g; $s =~ s/^ | $//g; return $s;
}
sub version_cmp {
  my ($x,$y)=@_; my @x=split /\./,$x; my @y=split /\./,$y;
  for (0..3) { my $n=$x[$_] <=> $y[$_]; return $n if $n; } return 0;
}
open my $in,'<',$ARGV[0] or die "Cannot read release notes: $!\n";
my $html=do { local $/; <$in> }; close $in;
my %releases;
my %months=(jan=>1,feb=>2,mar=>3,apr=>4,may=>5,jun=>6,jul=>7,aug=>8,sep=>9,oct=>10,nov=>11,dec=>12);
while ($html =~ m{<h2\b[^>]*>(.*?)</h2>(.*?)(?=<h[12]\b|\z)}gis) {
  my ($heading,$body)=(clean($1),$2);
  next unless $heading =~ /^Cisco Secure Client (5\.1\.\d+\.\d+) New Features$/;
  my $v=$1; my $date='';
  if ($body =~ m{<sup\b[^>]*>(.*?)</sup>}is) {
    my $text=clean($1);
    if ($text =~ /^([A-Za-z]+)\.?\s+(\d{1,2}),?\s+(\d{4})$/) {
      my ($month,$day,$year)=($months{lc substr($1,0,3)},$2,$3);
      die "Unrecognized date for $v\n" unless $month && $day>=1 && $day<=31;
      $date=sprintf '%04d-%02d-%02d',$year,$month,$day;
    } else { die "Unexpected release date for $v: $text\n"; }
  }
  $releases{$v}=$date;
}
die "No Secure Client 5.1 release headings found; history unchanged.\n" unless keys %releases;
my @versions=sort { version_cmp($a,$b) } keys %releases;
my $latest=$versions[-1];
# Require agreement with the document's main release heading.
my @titles=($html =~ m{<h1\b[^>]*>(.*?)</h1>}gis);
die "Latest release and document title disagree; history unchanged.\n"
  unless grep { clean($_) eq "Release Notes for Cisco Secure Client, Release $latest" } @titles;
my $history=$ENV{HISTORY_FILE};
my $header="version,release_date,first_seen,source_url";
my %saved;
if (-e $history) {
  open my $old,'<',$history or die "Cannot read history: $!\n";
  my $h=<$old>; chomp $h;
  die "Invalid history header\n" unless $h eq $header;
  while (<$old>) {
    chomp; my @row=split /,/, $_,-1;
    die "Invalid history row\n" unless @row==4 && $row[0] =~ /^5\.1\.\d+\.\d+$/ && $row[2] =~ /^\d{4}-\d{2}-\d{2}$/;
    $saved{$row[0]}=\@row;
  }
  close $old;
}
my @previous=sort { version_cmp($a,$b) } keys %saved;
my $previous=@previous ? $previous[-1] : '';
die "Latest documented version is older than saved version; history unchanged.\n"
  if $previous && version_cmp($latest,$previous)<0;
my $status=!$previous ? 'baseline' : version_cmp($latest,$previous)>0 ? 'new_version' : 'unchanged';
my $seen=strftime('%Y-%m-%d',gmtime);
my $added=0;
for my $v (@versions) {
  if (!$saved{$v}) { $saved{$v}=[$v,$releases{$v},$seen,$ENV{SOURCE_URL}]; $added++; }
  elsif ($releases{$v} ne '') { $saved{$v}[1]=$releases{$v}; }
}
make_path(dirname($history));
my ($out,$temporary)=tempfile('.history-XXXXXX',DIR=>dirname($history),UNLINK=>0);
print $out "$header\n";
for my $v (sort { version_cmp($b,$a) } keys %saved) { print $out join(',',@{$saved{$v}}),"\n"; }
close $out or die "Cannot save history: $!\n";
my $latest_file=$ENV{LATEST_FILE};
die "JSON and CSV must use different paths\n" if $latest_file eq $history;
make_path(dirname($latest_file));
my ($json_out,$json_temporary)=tempfile('.latest-XXXXXX',DIR=>dirname($latest_file),UNLINK=>0);
print $json_out JSON::PP->new->canonical->pretty->encode({
  version=>$latest,
  release_date=>$releases{$latest} ne '' ? $releases{$latest} : undef
});
close $json_out or die "Cannot save latest JSON: $!\n";
rename $temporary,$history or die "Cannot replace history: $!\n";
rename $json_temporary,$latest_file or die "Cannot replace latest JSON: $!\n";
print "status=$status\nlatest=$latest\nprevious=$previous\nadded_history_entries=$added\nhistory=$history\nlatest_file=$latest_file\n";
if ($ENV{GITHUB_OUTPUT}) {
  open my $gh,'>>',$ENV{GITHUB_OUTPUT} or die "Cannot write GitHub output: $!\n";
  print $gh "status=$status\nlatest=$latest\nprevious=$previous\n"; close $gh;
}
PERL
