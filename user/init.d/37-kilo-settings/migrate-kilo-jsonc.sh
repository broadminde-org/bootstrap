#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 SOURCE_CONFIG LIVE_CONFIG" >&2
  exit 2
fi

source_config="$1"
live_config="$2"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command_file="$script_dir/privilege-commands.txt"
# This is the literal Kilo config value, not a shell path.
# shellcheck disable=SC2088
rules_glob='~/.config/kilo/rules/*.md'

manual_merge() {
  local command
  echo "Error: cannot safely migrate $live_config: $1" >&2
  echo "Manual merge required: add \"instructions\": [\"$rules_glob\"] at the root," >&2
  echo "and add these entries to the single permission.bash object:" >&2
  if [[ -f "$command_file" ]]; then
    while IFS= read -r command; do
      [[ -n "$command" && "$command" != \#* ]] || continue
      echo "  \"$command\": \"deny\"," >&2
      echo "  \"$command *\": \"deny\"," >&2
    done < "$command_file"
  else
    echo "  (canonical command list unavailable: $command_file)" >&2
  fi
  echo "Then validate the effective configuration with: kilo config check" >&2
  exit 1
}

[[ -f "$source_config" ]] || manual_merge "source configuration is missing"
[[ -f "$command_file" ]] || manual_merge "canonical privilege command list is missing"
if [[ -L "$live_config" ]]; then
  manual_merge "the live configuration is a symlink"
fi

live_dir="$(dirname "$live_config")"
mkdir -p "$live_dir"
candidate="$(mktemp "$live_config.candidate.XXXXXX")"
backup=""
installed=false
validated=false
had_live=false

rollback() {
  status=$?
  trap - EXIT HUP INT TERM
  if [[ "$installed" == true && "$validated" != true ]]; then
    if [[ "$had_live" == true ]]; then
      mv -f "$backup" "$live_config"
      backup=""
      echo "Restored the original $live_config after unsuccessful validation." >&2
    else
      rm -f "$live_config"
      echo "Removed the unvalidated $live_config." >&2
    fi
  fi
  rm -f "$candidate"
  [[ -z "$backup" ]] || rm -f "$backup"
  exit "$status"
}
trap rollback EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ ! -e "$live_config" ]]; then
  cp "$source_config" "$candidate"
  report="created from the managed source"
else
  [[ -f "$live_config" ]] || manual_merge "the live path is not a regular file"
  had_live=true
  chmod --reference="$live_config" "$candidate"

  if ! report_raw="$(perl - "$live_config" "$candidate" "$command_file" "$source_config" 2>&1 <<'PERL'
use strict;
use warnings;

my ($input, $output, $commands_file, $source) = @ARGV;
open my $in, '<', $input or die "cannot read $input: $!\n";
my @lines = <$in>;
close $in;
my $content = join '', @lines;
if ($content =~ /\A\s*\{\s*"\$schema"\s*:\s*"https:\/\/app\.kilo\.ai\/config\.json"\s*,?\s*\}\s*\z/) {
  open my $src, '<', $source or die "cannot read $source: $!\n";
  open my $out, '>', $output or die "cannot write $output: $!\n";
  print {$out} <$src>;
  close $src or die "cannot close $source: $!\n";
  close $out or die "cannot close $output: $!\n";
  print 'replaced empty default with the managed source';
  exit 0;
}
open my $commands_in, '<', $commands_file or die "cannot read $commands_file: $!\n";
chomp(my @commands = grep { /\S/ && !/^\s*#/ } <$commands_in>);
close $commands_in;

sub fail_migration { die "STRUCTURE: $_[0]\n" }
sub structural_line {
  my ($line) = @_;
  $line =~ s{//.*$}{};
  $line =~ s{"(?:\\.|[^"\\])*"}{""}g;
  return $line;
}

my @instructions;
my @permission_starts;
my @bash_starts;
my $depth = 0;
my @permission_stack;
for my $i (0 .. $#lines) {
  my $line = $lines[$i];
  if ($line =~ /^\s*"instructions"\s*:/) {
    push @instructions, [$i, $depth, $line];
  }
  if ($line =~ /^(\s*)"permission"\s*:\s*\{\s*(?:\/\/.*)?$/) {
    push @permission_starts, [$i, $depth];
    push @permission_stack, [$i, $depth + 1];
  }
  if ($line =~ /^(\s*)"bash"\s*:\s*\{\s*(?:\/\/.*)?$/) {
    my @owners = grep { $_->[1] == $depth } @permission_stack;
    push @bash_starts, [$i, $depth, scalar @owners];
  }
  my $structural = structural_line($line);
  my $opens = () = $structural =~ /\{/g;
  my $closes = () = $structural =~ /\}/g;
  $depth += $opens - $closes;
  fail_migration("unbalanced braces") if $depth < 0;
  @permission_stack = grep { $_->[1] <= $depth } @permission_stack;
}
fail_migration("unbalanced braces") if $depth != 0;

if (@instructions > 1) {
  fail_migration("duplicate instructions properties");
}
my $add_instructions = 0;
if (@instructions == 1) {
  my ($index, $property_depth, $line) = @{$instructions[0]};
  fail_migration("instructions is not a root property") if $property_depth != 1;
  fail_migration("instructions has a different value")
    unless $line =~ /^\s*"instructions"\s*:\s*\[\s*"~\/\.config\/kilo\/rules\/\*\.md"\s*\]\s*,?\s*(?:\/\/.*)?$/;
} else {
  my @root_open = grep { $lines[$_] =~ /^\s*\{\s*(?:\/\/.*)?$/ } 0 .. $#lines;
  fail_migration("root opening brace is not recognizable") unless @root_open == 1 && $root_open[0] == 0;
  $add_instructions = 1;
}

fail_migration("expected exactly one recognizable permission object") unless @permission_starts == 1;
fail_migration("expected exactly one recognizable permission.bash object") unless @bash_starts == 1;
my ($bash_start, $bash_depth, $owner_count) = @{$bash_starts[0]};
my ($permission_start, $permission_depth) = @{$permission_starts[0]};
fail_migration("permission is not a root property") unless $permission_depth == 1;
fail_migration("bash is not directly inside permission") unless $bash_depth == 2 && $owner_count == 1 && $permission_start < $bash_start;

my $bash_end;
$depth = $bash_depth + 1;
for my $i ($bash_start + 1 .. $#lines) {
  my $structural = structural_line($lines[$i]);
  my $opens = () = $structural =~ /\{/g;
  my $closes = () = $structural =~ /\}/g;
  $depth += $opens - $closes;
  if ($depth == $bash_depth) {
    $bash_end = $i;
    last;
  }
}
fail_migration("bash object has no recognizable closing brace") unless defined $bash_end;

my %managed = map { $_ => 1, "$_ *" => 1 } @commands;
my %seen;
my @anchors;
for my $i ($bash_start + 1 .. $bash_end - 1) {
  # Block comments are not recognized; fail loudly instead of misreading them.
  fail_migration("block comment inside permission.bash")
    if $lines[$i] =~ m{/\*} || $lines[$i] =~ m{\*/};
  # Strip line comments before scanning so commented-out keys and anchors are
  # neither mistaken for real entries nor counted as duplicates.
  (my $text = $lines[$i]) =~ s{//.*$}{};
  while ($text =~ /"((?:\\.|[^"\\])*)"\s*:\s*"([^"]*)"/g) {
    my ($key, $value) = ($1, $2);
    push @anchors, $i if $key eq '*' && $value eq 'allow';
    next unless $managed{$key};
    fail_migration("duplicate managed key '$key'") if $seen{$key}++;
    fail_migration("managed key '$key' is '$value', not 'deny'") unless $value eq 'deny';
  }
}
# Zero or one anchor is recognizable; more than one is ambiguous. An
# anchor-less allowlist is common on existing hosts and is safe to migrate:
# adding denials only ever restricts, never loosens.
fail_migration("ambiguous \"*\": \"allow\" anchors in permission.bash") if @anchors > 1;

my @missing = grep { !$seen{$_} } map { ($_, "$_ *") } @commands;
my @output = @lines;
if (@missing) {
  my ($insert_at, $indent);
  if (@anchors == 1) {
    $insert_at = $anchors[0] + 1;
    ($indent) = $lines[$anchors[0]] =~ /^(\s*)/;
  } else {
    # No anchor: insert at the top of the bash object, matching the indent of
    # its first entry (or the bash key's indent plus two spaces when empty).
    my $first;
    for my $i ($bash_start + 1 .. $bash_end - 1) {
      next unless $lines[$i] =~ /\S/;
      $first = $i;
      last;
    }
    if (defined $first) {
      $insert_at = $first;
      ($indent) = $lines[$first] =~ /^(\s*)/;
    } else {
      $insert_at = $bash_end;
      ($indent) = $lines[$bash_start] =~ /^(\s*)/;
      $indent .= '  ';
    }
  }
  my @insert = map { $indent . '"' . $_ . "\": \"deny\",\n" } @missing;
  splice @output, $insert_at, 0, @insert;
}
if ($add_instructions) {
  splice @output, 1, 0, "  \"instructions\": [\"~/.config/kilo/rules/*.md\"],\n";
}

open my $out, '>', $output or die "cannot write $output: $!\n";
print {$out} @output;
close $out or die "cannot close $output: $!\n";
my @changes;
push @changes, 'instructions' if $add_instructions;
push @changes, @missing;
print @changes ? 'added ' . join(', ', @changes) : 'no migration needed';
PERL
)"; then
    # Structural failures die with a "STRUCTURE: " prefix; report the reason.
    report_reason="${report_raw#STRUCTURE: }"
    manual_merge "${report_reason%%$'\n'*}"
  fi
  report="$report_raw"
fi

if [[ "$had_live" == true ]] && cmp -s "$candidate" "$live_config"; then
  rm -f "$candidate"
  candidate="$(mktemp "$live_config.candidate.XXXXXX")"
  echo "  kilo.jsonc unchanged: $report"
  if ! kilo config check; then
    echo "Error: kilo config check rejected the unchanged effective configuration." >&2
    exit 1
  fi
  validated=true
  exit 0
fi

if [[ "$had_live" == true ]]; then
  backup="$(mktemp "$live_config.backup.XXXXXX")"
  cp -p "$live_config" "$backup"
  chmod --reference="$live_config" "$candidate"
fi
mv -f "$candidate" "$live_config"
installed=true

if ! kilo config check; then
  echo "Error: kilo config check rejected the migrated effective configuration." >&2
  exit 1
fi

validated=true
[[ -z "$backup" ]] || rm -f "$backup"
backup=""
echo "  kilo.jsonc $report; validated with kilo config check"
