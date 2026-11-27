#!/usr/bin/env bash
set -euo pipefail

preflight=false
if [[ "${1:-}" == --preflight ]]; then
  preflight=true
  shift
fi
if [[ $# -ne 2 ]]; then
  echo 'Usage: migrate-kilo-jsonc.sh [--preflight] SOURCE_CONFIG LIVE_CONFIG' >&2
  exit 2
fi

source_config="$1"
live_config="$2"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command_file="$script_dir/privilege-commands.txt"
patterns_file="$script_dir/managed-deny-patterns.txt"

manual_merge() {
  # Never emit live values, arbitrary keys, paths, parser errors, or client output.
  echo "Error: safe kilo.jsonc migration refused: $1" >&2
  echo 'Manual merge required: review the canonical template and preserve unrelated settings.' >&2
  echo 'Use one root instructions array and one permission.bash object.' >&2
  echo 'Place managed Bash denials AFTER all local rules that can overlap them.' >&2
  echo 'Add canonical playwright_*/svelte_* denials and read mcp:playwright:*/mcp:svelte:* denials last.' >&2
  echo 'Preserve sensitive-read prompts; scalar/conflicting policies require manual review.' >&2
  echo 'Validate only under separately authorized client execution; config validity is not enforcement proof.' >&2
  exit 1
}

check_path() {
  local path="$1"
  while :; do
    [[ ! -L "$path" ]] || manual_merge 'a relevant path is redirected'
    [[ "$path" != / && "$path" != . ]] || break
    path="$(dirname "$path")"
  done
}

for path in "$source_config" "$live_config" "$command_file" "$patterns_file"; do
  check_path "$path"
done
[[ -f "$source_config" && -f "$command_file" && -f "$patterns_file" ]] || manual_merge 'a canonical input is missing'
[[ ! -e "$live_config" || -f "$live_config" ]] || manual_merge 'the live path is not a regular file'
[[ ! "$source_config" -ef "$live_config" ]] || manual_merge 'source and live paths identify the same file'

umask 077
live_dir="$(dirname "$live_config")"
scratch=''
candidate=''
backup=''
installed=false
validated=false
had_live=false
[[ ! -e "$live_config" ]] || had_live=true

rollback() {
  local status=$?
  trap - EXIT
  # A second handled interruption must not abort restoration half-way through.
  # The process exits below, so no caller signal disposition needs restoration.
  trap '' HUP INT TERM
  if [[ "$installed" == true && "$validated" != true ]]; then
    if [[ "$had_live" == true ]]; then
      if ! mv -f "$backup" "$live_config" 2>/dev/null; then
        echo 'Error: rollback failed; original bytes/mode remain in private migration staging. Stop and recover manually.' >&2
        exit 1
      fi
      echo 'Restored the original kilo.jsonc bytes and mode after unsuccessful validation.' >&2
    else
      if ! rm -f "$live_config" 2>/dev/null; then
        echo 'Error: rollback could not restore original absence. Stop and recover manually.' >&2
        exit 1
      fi
      echo 'Restored original kilo.jsonc absence after unsuccessful validation.' >&2
    fi
  fi
  rm -f "$candidate" "$backup" 2>/dev/null || status=1
  rmdir "$scratch" 2>/dev/null || status=1
  exit "$status"
}
if [[ "$preflight" != true ]]; then
  mkdir -p "$live_dir" 2>/dev/null || manual_merge 'cannot prepare the destination directory'
  scratch="$(mktemp -d "$live_dir/.kilo-migration.XXXXXX" 2>/dev/null)" || manual_merge 'cannot create private migration staging'
  candidate="$scratch/candidate"
  backup="$scratch/original"
  trap rollback EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
fi

input_config="$source_config"
[[ "$had_live" != true ]] || input_config="$live_config"
# Preflight shares admission, including the final splice syntax check, but has
# no output file, staging directory, config write, or client initialization.
# The parser edits only selected member spans, not serialized live values.
# JSON::PP is core Perl; parsing requires no installation or client startup.
if ! perl - "$input_config" "$candidate" "$command_file" "$patterns_file" "$source_config" "$preflight" >/dev/null 2>&1 <<'PERL'
use strict;
use warnings;
use JSON::PP ();
use Encode ();

my ($input, $output, $commands_file, $patterns_file, $source, $preflight) = @ARGV;
sub fail { die "unsupported configuration structure\n" }
sub load {
  open my $fh, '<:raw', $_[0] or fail();
  local $/;
  my $text = <$fh>;
  close $fh or fail();
  # Validate encoding without changing the raw byte offsets used for splicing.
  Encode::decode('UTF-8', $text, Encode::FB_CROAK | Encode::LEAVE_SRC);
  return $text;
}

# A bounded JSONC syntax reader, not a permission evaluator. Token spans retain
# comments, formatting, and unrelated values, including URLs containing //.
sub parse {
  my ($text) = @_;
  my @tokens;
  pos($text) = 0;
  while (pos($text) < length($text)) {
    next if $text =~ /\G(?:\s+|\/\/[^\r\n]*|\/\*[\s\S]*?\*\/)/gc;
    my $start = pos($text);
    if ($text =~ /\G("(?:\\["\\\/bfnrt]|\\u[0-9a-fA-F]{4}|[^"\\\x00-\x1f])*")/gc) {
      my $value = JSON::PP->new->utf8->allow_nonref->decode($1);
      push @tokens, { type => 'string', value => $value, start => $start, end => pos($text) };
    } elsif ($text =~ /\G([{}\[\]:,])/gc) {
      push @tokens, { type => $1, start => $start, end => pos($text) };
    } elsif ($text =~ /\G(?:true|false|null|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)/gc) {
      push @tokens, { type => 'atom', start => $start, end => pos($text) };
    } else { fail() }
  }
  my $at = 0;
  my $node;
  $node = sub {
    my ($depth) = @_;
    fail() if $depth > 128;
    my $token = $tokens[$at++] or fail();
    my $type = $token->{type};
    return { %$token } if $type eq 'string' || $type eq 'atom';
    fail() unless $type eq '{' || $type eq '[';
    my $close = $type eq '{' ? '}' : ']';
    my (@entries, %seen);
    while (($tokens[$at] // {})->{type} && $tokens[$at]->{type} ne $close) {
      my ($key, $start);
      if ($type eq '{') {
        my $key_token = $tokens[$at++] or fail();
        fail() unless $key_token->{type} eq 'string';
        $key = $key_token->{value};
        $start = $key_token->{start};
        fail() if $seen{$key}++;
        fail() unless ($tokens[$at++] // {})->{type} eq ':';
      }
      my $value = $node->($depth + 1);
      my $entry = { key => $key, start => $start // $value->{start}, value => $value };
      if (($tokens[$at] // {})->{type} eq ',') {
        $entry->{comma} = $tokens[$at++];
      } else {
        fail() unless ($tokens[$at] // {})->{type} eq $close;
      }
      push @entries, $entry;
    }
    my $last = $tokens[$at++] or fail();
    fail() unless $last->{type} eq $close;
    return { type => $type, start => $token->{start}, end => $last->{end}, close => $last->{start}, entries => \@entries };
  };
  my $root = $node->(0);
  fail() unless $at == @tokens && $root->{type} eq '{';
  return $root;
}

sub member {
  my ($object, $key) = @_;
  fail() unless $object->{type} eq '{';
  return (grep { $_->{key} eq $key } @{$object->{entries}})[0];
}
sub object_member {
  my $entry = member(@_) or fail();
  fail() unless $entry->{value}->{type} eq '{';
  return $entry->{value};
}
sub deny {
  my ($entry) = @_;
  fail() unless $entry->{value}->{type} eq 'string' && $entry->{value}->{value} eq 'deny';
}
sub permission_name_matches {
  # v7.8.17 util/wildcard.ts; used only to reject outer rules that could
  # reopen the whole Bash/read object, not as an enforcement evaluator.
  my ($pattern, $name) = @_;
  $pattern =~ s{\\}{/}g;
  my $optional_tail = $pattern =~ s/ \*\z//;
  my $regex = quotemeta($pattern);
  $regex =~ s/\\\*/.*/g;
  $regex =~ s/\\\?/./g;
  $regex .= '( .*)?' if $optional_tail;
  return $name =~ /\A$regex\z/s;
}
sub list {
  return grep { length && !/^\s*#/ } split /\r?\n/, load($_[0]);
}

my $text = load($input);
my $root = parse($text);
my $canonical = parse(load($source));
my $source_permission = object_member($canonical, 'permission');
my $source_bash = object_member($source_permission, 'bash');
my @managed_bash = ((map { ($_, "$_ *") } list($commands_file)), list($patterns_file));
my %bash_set;
for my $key (@managed_bash) {
  fail() if $bash_set{$key}++;
  deny(member($source_bash, $key) // fail());
}
my @tools = ('playwright_*', 'svelte_*');
deny(member($source_permission, $_) // fail()) for @tools;
my @resources = ('mcp:playwright:*', 'mcp:svelte:*');
my $source_read = object_member($source_permission, 'read');
deny(member($source_read, $_) // fail()) for @resources;

# The schema-only initializer has no user policy to preserve.
if (@{$root->{entries}} == 1 && member($root, '$schema') &&
    member($root, '$schema')->{value}->{type} eq 'string' &&
    member($root, '$schema')->{value}->{value} eq 'https://app.kilo.ai/config.json') {
  exit 0 if $preflight eq 'true';
  open my $out, '>:raw', $output or fail();
  print {$out} load($source) or fail();
  close $out or fail();
  exit 0;
}

my @edits;
my %append;
my %objects;
sub add {
  my ($object, $key, $value) = @_;
  push @{$append{$object->{start}}}, JSON::PP->new->allow_nonref->encode($key) . ': ' . $value;
  $objects{$object->{start}} = $object;
}
sub tail_denials {
  my ($object, @keys) = @_;
  my %selected = map { $_ => 1 } @keys;
  my @entries = @{$object->{entries}};
  my @present = grep { $selected{$_->{key}} } @entries;
  deny($_) for @present;
  # Leave an already complete final deny block byte-identical, regardless of
  # internal key order. Otherwise relocate ALL managed keys after local rules.
  my $complete_tail = @present == @keys && !$append{$object->{start}};
  for my $i (0 .. $#entries) {
    $complete_tail = 0 if $i >= @entries - @keys && !$selected{$entries[$i]->{key}};
  }
  return if $complete_tail;
  for my $entry (@present) {
    my $end = $entry->{comma} ? $entry->{comma}->{end} : $entry->{value}->{end};
    push @edits, [$entry->{start}, $end - $entry->{start}, ''];
  }
  my @keep = grep { !$selected{$_->{key}} } @entries;
  $objects{$object->{start}} = { %$object, entries => \@keep };
  push @{$append{$object->{start}}}, map { JSON::PP->new->allow_nonref->encode($_) . ': "deny"' } @keys;
}

my $instructions = member($root, 'instructions');
if ($instructions) {
  my $value = $instructions->{value};
  fail() unless $value->{type} eq '[' && @{$value->{entries}} == 1 &&
    $value->{entries}->[0]->{value}->{type} eq 'string' &&
    $value->{entries}->[0]->{value}->{value} eq '~/.config/kilo/rules/*.md';
} else {
  add($root, 'instructions', '["~/.config/kilo/rules/*.md"]');
}
my $permission = object_member($root, 'permission');
# Outer tool rules are scalar actions or one-level pattern/action maps. Nested
# policy objects are unfamiliar, not safe unrelated content to migrate around.
for my $entry (@{$permission->{entries}}) {
  my $value = $entry->{value};
  my @actions = $value->{type} eq '{' ? map { $_->{value} } @{$value->{entries}} : ($value);
  for my $action (@actions) {
    fail() unless $action->{type} eq 'string' && $action->{value} =~ /\A(?:allow|ask|deny)\z/;
  }
}
my $bash = object_member($permission, 'bash');
my $read = member($permission, 'read');
# A later permission-name wildcard can override the entire Bash/read object.
# Moving that object would also reopen unrelated local allowances. Reject this
# unfamiliar ordering rather than silently widening those permissions.
for my $entry (@{$permission->{entries}}) {
  next if $entry->{key} eq 'playwright_*' || $entry->{key} eq 'svelte_*';
  next unless $entry->{key} =~ /[*?]/;
  fail() if (permission_name_matches($entry->{key}, 'bash') &&
             $entry->{start} > $bash->{start}) ||
    ($read && permission_name_matches($entry->{key}, 'read') &&
     $entry->{start} > $read->{start});
}
# Do not treat a malformed/scalar Bash value as a safe additive migration.
for my $entry (@{$bash->{entries}}) {
  fail() unless $entry->{value}->{type} eq 'string' && $entry->{value}->{value} =~ /\A(?:allow|ask|deny)\z/;
}
tail_denials($bash, @managed_bash);
if ($read) {
  fail() unless $read->{value}->{type} eq '{';
  for my $entry (@{$read->{value}->{entries}}) {
    fail() unless $entry->{value}->{type} eq 'string' && $entry->{value}->{value} =~ /\A(?:allow|ask|deny)\z/;
  }
  tail_denials($read->{value}, @resources);
} else {
  add($permission, 'read', '{"mcp:playwright:*": "deny", "mcp:svelte:*": "deny"}');
}
tail_denials($permission, @tools);

for my $id (keys %append) {
  my $object = $objects{$id};
  my @entries = @{$object->{entries}};
  my $block = "\n" . join('', map { "    $_,\n" } @{$append{$id}});
  if (@entries && !$entries[-1]->{comma}) {
    if ($entries[-1]->{value}->{end} == $object->{close}) {
      # Compact objects need one insertion: two zero-length edits at the same
      # byte offset would put the separator after the appended property block.
      $block = ',' . $block;
    } else {
      push @edits, [$entries[-1]->{value}->{end}, 0, ','];
    }
  }
  push @edits, [$object->{close}, 0, $block];
}
for my $edit (sort { $b->[0] <=> $a->[0] } @edits) {
  substr($text, $edit->[0], $edit->[1], $edit->[2]);
}
parse($text); # Reject a bad splice before installing any candidate.
exit 0 if $preflight eq 'true';
open my $out, '>:raw', $output or fail();
print {$out} $text or fail();
close $out or fail();
PERL
then
  manual_merge 'unsupported, ambiguous, duplicate, or conflicting configuration structure'
fi
if [[ "$preflight" == true ]]; then
  echo '  kilo.jsonc structural preflight passed; no files written or client initialized.'
  exit 0
fi

# Client diagnostics may contain arbitrary live values. Never relay or retain
# them. This validation runs only when the operator executes this migrator.
if [[ "$had_live" == true ]] && cmp -s "$candidate" "$live_config"; then
  if ! kilo config check >/dev/null 2>&1; then
    manual_merge 'client validation rejected the unchanged effective configuration'
  fi
  validated=true
  echo '  kilo.jsonc unchanged; client configuration validation passed (not enforcement qualification).'
  exit 0
fi

if [[ "$had_live" == true ]]; then
  cp -p "$live_config" "$backup" 2>/dev/null || manual_merge 'cannot preserve original bytes and mode'
  chmod --reference="$live_config" "$candidate" 2>/dev/null || manual_merge 'cannot preserve the live mode'
fi
# Arm rollback before rename so a signal between rename and the next shell
# statement cannot discard the original backup.
installed=true
mv -f "$candidate" "$live_config" 2>/dev/null || manual_merge 'cannot install the staged configuration'
if ! kilo config check >/dev/null 2>&1; then
  manual_merge 'client validation rejected the migrated effective configuration'
fi
validated=true
echo '  kilo.jsonc managed policy migrated; client configuration validation passed (not enforcement qualification).'
