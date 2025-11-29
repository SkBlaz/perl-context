#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use File::Find;
use File::Spec;
use File::Path 'remove_tree';
use File::Temp 'tempdir';
use Cwd 'abs_path';
use Getopt::Long;
binmode STDOUT, ':encoding(UTF-8)';

# ------------------------------------------------------------
# CLI options
#   --git_url URL   : clone URL into a temp dir and dump that repo
#   [path]          : path to repo (default: .) when --git_url is not used
# ------------------------------------------------------------

my $git_url;
my $help;

GetOptions(
    'git_url=s' => \$git_url,
    'help'      => \$help,
) or die "Usage: $0 [--git_url URL] [path]\n";

if ($help) {
    print "Usage:\n";
    print "  $0 [--git_url URL] [path]\n\n";
    print "Examples:\n";
    print "  $0 .\n";
    print "  $0 /path/to/repo\n";
    print "  $0 --git_url https://github.com/SkBlaz/py3plex.git\n";
    exit 0;
}

my $tmp_root;
my $root;

if ($git_url) {
    # clone into a temp dir
    $tmp_root = tempdir("pcontext-XXXXXX", CLEANUP => 0);
    my $target = "$tmp_root/repo";

    print "# Cloning $git_url into $target\n";
    my $rc = system('git', 'clone', '--depth', '1', $git_url, $target);
    if ($rc != 0) {
        die "git clone failed with exit code " . ($rc >> 8) . "\n";
    }

    $root = abs_path($target);
} else {
    my $path = shift @ARGV // '.';
    $root = abs_path($path);
}

# ensure temp clone is removed when script exits
END {
    if (defined $tmp_root && -d $tmp_root) {
        remove_tree($tmp_root, { error => \my $err });
        # ignore errors; this is best-effort cleanup
    }
}

# ------------------------------------------------------------
# Config via environment variables
#   REPO_DUMP_MAX_BYTES     - max size per file (bytes)
#   REPO_DUMP_MAX_LINES     - max lines per chunk (0 = no chunking)
#   REPO_DUMP_LINE_NUMBERS  - if set, prefix lines with "NNNN| "
#   REPO_DUMP_ONLY_EXT      - comma-separated extensions to include (e.g. "py,ts,tsx")
#   REPO_DUMP_EXCLUDE       - extra ignore patterns, comma-separated (glob-ish)
# ------------------------------------------------------------

my $MAX_BYTES  = $ENV{REPO_DUMP_MAX_BYTES}    || 300_000;
my $MAX_LINES  = defined $ENV{REPO_DUMP_MAX_LINES}
                 ? $ENV{REPO_DUMP_MAX_LINES}
                 : 1200;
my $LINE_NUMS  = $ENV{REPO_DUMP_LINE_NUMBERS} ? 1 : 0;
my $ONLY_EXTS  = $ENV{REPO_DUMP_ONLY_EXT}     || '';
my $EXCLUDE_PAT= $ENV{REPO_DUMP_EXCLUDE}      || '';

my %only_ext;
if (length $ONLY_EXTS) {
    %only_ext = map { lc($_) => 1 }
                grep { length } split /\s*,\s*/, $ONLY_EXTS;
}

# ------------------------------------------------------------
# Language mapping
# ------------------------------------------------------------

my %ext_to_lang = (
    pl   => 'perl',    pm    => 'perl',
    py   => 'python',
    rb   => 'ruby',
    js   => 'javascript', mjs  => 'javascript', cjs => 'javascript',
    ts   => 'typescript', tsx  => 'tsx', jsx    => 'jsx',
    java => 'java',
    c    => 'c', h => 'c',
    cpp  => 'cpp', cc => 'cpp', cxx => 'cpp', hh => 'cpp', hpp => 'cpp',
    go   => 'go',
    rs   => 'rust',
    php  => 'php',
    cs   => 'csharp',
    sh   => 'bash', zsh => 'zsh',
    md   => 'markdown', markdown => 'markdown',
    json => 'json',
    yml  => 'yaml', yaml => 'yaml',
    html => 'html', htm  => 'html',
    css  => 'css',
    sql  => 'sql',
    kt   => 'kotlin',
    swift=> 'swift',
    r    => 'r',
    hs   => 'haskell',
    toml => 'toml',
);

my %lang_name = (
    perl        => 'Perl',
    python      => 'Python',
    ruby        => 'Ruby',
    javascript  => 'JavaScript',
    typescript  => 'TypeScript',
    tsx         => 'TypeScript (TSX)',
    jsx         => 'JavaScript (JSX)',
    java        => 'Java',
    c           => 'C / headers',
    cpp         => 'C++',
    go          => 'Go',
    rust        => 'Rust',
    php         => 'PHP',
    csharp      => 'C#',
    bash        => 'Shell (bash)',
    zsh         => 'Shell (zsh)',
    markdown    => 'Markdown',
    json        => 'JSON',
    yaml        => 'YAML',
    html        => 'HTML',
    css         => 'CSS',
    sql         => 'SQL',
    kotlin      => 'Kotlin',
    swift       => 'Swift',
    r           => 'R',
    haskell     => 'Haskell',
    toml        => 'TOML',
    text        => 'Text / other',
);

sub lang_display_name {
    my ($k) = @_;
    $k ||= 'text';
    return $lang_name{$k} || ucfirst($k);
}

# ------------------------------------------------------------
# .gitignore + extra excludes
# ------------------------------------------------------------

sub glob_to_regex {
    my ($pat) = @_;
    $pat =~ s/^\s+|\s+$//g;
    $pat =~ s{^\./}{};
    return if $pat eq '' || $pat =~ /^#/;

    my $re = quotemeta($pat);
    $re =~ s/\\\*/.*/g;
    $re =~ s/\\\?/./g;
    return qr/^$re$/;
}

my @ignore_re;
my $gitignore = "$root/.gitignore";

if (-f $gitignore && open my $gi, '<', $gitignore) {
    while (my $pat = <$gi>) {
        chomp $pat;
        my $re = glob_to_regex($pat);
        push @ignore_re, $re if $re;
    }
    close $gi;
}

if (length $EXCLUDE_PAT) {
    for my $pat (split /\s*,\s*/, $EXCLUDE_PAT) {
        my $re = glob_to_regex($pat);
        push @ignore_re, $re if $re;
    }
}

sub ignored {
    my ($rel) = @_;
    for my $re (@ignore_re) {
        return 1 if $rel =~ $re;
    }
    return 0;
}

# ------------------------------------------------------------
# Role & hint classification
# ------------------------------------------------------------

sub file_role_and_flags {
    my ($rel, $ext, $lang_key) = @_;
    my $lc = lc $rel;
    my $category;
    my $is_config = 0;
    my $is_entry  = 0;

    # Entrypoints by language
    if ($lang_key && $lang_key eq 'python') {
        $is_entry = 1 if $lc =~ m{(^|/)(main|app|wsgi|asgi|manage)\.py$};
    } elsif ($lang_key && ($lang_key eq 'javascript' || $lang_key eq 'typescript' || $lang_key eq 'tsx' || $lang_key eq 'jsx')) {
        $is_entry = 1 if $lc =~ m{(^|/)(src/)?(index|main|app|server|cli)\.(js|jsx|ts|tsx)$};
    } elsif ($lang_key && $lang_key eq 'go') {
        $is_entry = 1 if $lc =~ m{(^|/)cmd/[^/]+/main\.go$} || $lc =~ m{(^|/)main\.go$};
    } elsif ($lang_key && $lang_key eq 'rust') {
        $is_entry = 1 if $lc =~ m{(^|/)src/main\.rs$} || $lc =~ m{(^|/)src/bin/[^/]+\.rs$};
    } elsif ($lang_key && $lang_key eq 'java') {
        $is_entry = 1 if $lc =~ m{(^|/)src/main/java/.+/(Main|Application)\.java$};
    }

    # Tests
    if ($lc =~ m{(^|/)(test|tests|spec|__tests__)/}
        || $lc =~ m{(^|/)test_}
        || $lc =~ m{_test\.[a-z0-9_]+$}
        || $lc =~ m{\.spec\.[a-z0-9_]+$}
        || $lc =~ m{\.test\.[a-z0-9_]+$}) {
        $category = 'test';
    }

    # Config / manifest
    my @config_names = qw(
        package.json tsconfig.json webpack.config.js webpack.config.ts
        vite.config.js vite.config.ts rollup.config.js rollup.config.ts
        babel.config.js babel.config.cjs babel.config.mjs
        jest.config.js jest.config.ts
        pyproject.toml setup.py requirements.txt Pipfile Pipfile.lock
        tox.ini setup.cfg
        Cargo.toml Cargo.lock
        go.mod go.sum
        Makefile CMakeLists.txt
        pom.xml build.gradle settings.gradle
        composer.json Gemfile Rakefile
    );

    for my $cfg (@config_names) {
        my $pat = lc $cfg;
        if (index($lc, "/$pat") >= 0 || substr($lc, -length($pat)) eq $pat) {
            $category = 'config' unless defined $category;
            $is_config = 1;
            last;
        }
    }

    # Docs
    if (!defined $category && $lc =~ m{(^|/)(docs?|doc/)} && $ext =~ /^(md|rst|txt)$/i) {
        $category = 'docs';
    }
    if (!defined $category && $lc =~ m{(^|/)(readme|changelog|license|copying)(\.|$)}) {
        $category = 'docs';
    }

    # Fallback
    if (!defined $category) {
        if (defined $lang_key && $lang_key ne '' && $ext !~ /^(md|txt|rst)$/i) {
            $category = 'source';
        } else {
            $category = 'other';
        }
    }

    return ($category, $is_config, $is_entry);
}

sub role_hint {
    my ($category, $lang_key, $rel, $is_config, $is_entry) = @_;
    my @bits;

    push @bits, 'probable application entrypoint' if $is_entry;

    if ($category eq 'test') {
        if ($lang_key && $lang_key eq 'python') {
            push @bits, 'Python tests (pytest/unittest style naming)';
        } elsif ($lang_key && ($lang_key eq 'javascript' || $lang_key eq 'typescript' || $lang_key eq 'tsx' || $lang_key eq 'jsx')) {
            push @bits, 'JS/TS tests (Jest/Vitest/Mocha style naming)';
        } elsif ($lang_key && $lang_key eq 'go') {
            push @bits, 'Go tests (*_test.go)';
        } elsif ($lang_key && $lang_key eq 'rust') {
            push @bits, 'Rust tests (unit/integration style)';
        } else {
            push @bits, 'Test code';
        }
    }

    if ($category eq 'docs') {
        push @bits, 'Documentation / README-style content';
    }

    if ($category eq 'config' && $is_config) {
        if    ($rel =~ /package\.json$/i)    { push @bits, 'Node.js package manifest (dependencies + scripts)'; }
        elsif ($rel =~ /pyproject\.toml$/i)  { push @bits, 'Python project configuration (PEP 621 / tooling)'; }
        elsif ($rel =~ /requirements\.txt$/i){ push @bits, 'Python dependencies list'; }
        elsif ($rel =~ /Cargo\.toml$/i)      { push @bits, 'Rust crate manifest'; }
        elsif ($rel =~ /go\.mod$/i)          { push @bits, 'Go module definition'; }
        elsif ($rel =~ /pom\.xml$/i)         { push @bits, 'Maven build configuration'; }
    }

    return @bits ? join(', ', @bits) : '';
}

# ------------------------------------------------------------
# Walk repo
# ------------------------------------------------------------

my @paths;
my @files;
my %is_dir;

find({
    no_chdir => 1,
    wanted   => sub {
        my $path = $File::Find::name;
        return if $path eq $root;

        if (-d _) {
            my ($name) = $path =~ m{([^/]+)$};
            if ($name =~ /^\.(git|svn|hg)$/
                || $name =~ /^(node_modules|dist|build|target|venv|__pycache__)$/) {
                $File::Find::prune = 1;
                return;
            }
        }

        my $rel = File::Spec->abs2rel($path, $root);
        return if ignored($rel);

        push @paths, $rel;
        if (-d _) {
            $is_dir{$rel} = 1;
        } elsif (-f _) {
            if (%only_ext) {
                my ($ext) = $rel =~ /\.([A-Za-z0-9_]+)$/;
                my $lex = lc($ext // '');
                return if !$lex || !$only_ext{$lex};
            }
            push @files, $rel;
        }
    },
}, $root);

@paths = sort @paths;
@files = sort @files;

# ------------------------------------------------------------
# Stats and metadata
# ------------------------------------------------------------

my %file_info;
my %lang_stats;
my %ext_count;
my $total_bytes = 0;
my $dir_count   = 0;

for my $p (@paths) {
    $dir_count++ if $is_dir{$p};
}

for my $rel (@files) {
    my $full = "$root/$rel";
    my $size = -s $full // 0;
    my $is_text = -T $full;

    $total_bytes += $size;

    my ($ext) = $rel =~ /\.([A-Za-z0-9_]+)$/;
    my $lex = lc($ext // '');
    $ext_count{$lex}++ if $lex;

    my $lang_key  = $ext_to_lang{$lex} || '';
    my $lang_id   = $lang_key || ($lex || 'text');
    my $lang_name = lang_display_name($lang_key || 'text');

    my ($category, $is_config, $is_entry) = file_role_and_flags($rel, $lex, $lang_key);

    $file_info{$rel} = {
        full       => $full,
        size       => $size,
        is_text    => $is_text,
        ext        => $lex,
        lang_key   => $lang_key,
        lang_id    => $lang_id,
        lang_name  => $lang_name,
        category   => $category,
        is_config  => $is_config,
        is_entry   => $is_entry,
    };

    my $ls = $lang_stats{$lang_id} ||= {
        name     => $lang_name,
        count    => 0,
        bytes    => 0,
        by_role  => {},
        entries  => [],
        configs  => [],
    };

    $ls->{count}++;
    $ls->{bytes} += $size;
    $ls->{by_role}{$category}++;
    push @{ $ls->{entries} }, $rel if $is_entry;
    push @{ $ls->{configs} }, $rel if $is_config;
}

my $file_count    = scalar @files;
my $approx_tokens = int(($total_bytes || 0) / 4) || 0;

my @key_files;
for my $rel (@files) {
    my $fi = $file_info{$rel} or next;
    my $cat = $fi->{category};
    if ($cat eq 'docs' || $fi->{is_entry} || $fi->{is_config}) {
        push @key_files, $rel;
    }
}

# ------------------------------------------------------------
# REPO OVERVIEW
# ------------------------------------------------------------

print "### REPO OVERVIEW\n\n";
print "Root: $root\n";
print "Dirs: $dir_count\n";
print "Files (included by filters): $file_count\n";
print "Approx total bytes (sum of file sizes): $total_bytes\n";
print "Approx tokens (~4 chars/token): $approx_tokens\n\n";

if (@key_files) {
    print "Key docs / entrypoints / configs (good starting points for the LLM):\n";
    for my $kf (sort @key_files) {
        my $fi = $file_info{$kf};
        my $tag = $fi->{category};
        $tag .= ", entrypoint-ish" if $fi->{is_entry};
        $tag .= ", config" if $fi->{is_config};
        print "- $kf [$tag]\n";
    }
    print "\n";
}

if (%ext_count) {
    print "By extension (raw counts):\n";
    for my $e (sort { $ext_count{$b} <=> $ext_count{$a} || $a cmp $b } keys %ext_count) {
        print "- $e: $ext_count{$e}\n";
    }
    print "\n";
}

# ------------------------------------------------------------
# LANGUAGE OVERVIEW
# ------------------------------------------------------------

print "### LANGUAGE OVERVIEW\n\n";

for my $lang_id (
    sort {
        ($lang_stats{$b}{bytes} <=> $lang_stats{$a}{bytes})
        || ($lang_stats{$b}{count} <=> $lang_stats{$a}{count})
        || ($lang_stats{$a}{name} cmp $lang_stats{$b}{name})
    } keys %lang_stats
) {
    my $ls = $lang_stats{$lang_id};
    my $tokens = int(($ls->{bytes} || 0) / 4);

    print "- $ls->{name} ($lang_id): $ls->{count} files, ~$tokens tokens\n";

    my @roles = qw(source test config docs other);
    my @role_lines;
    for my $r (@roles) {
        my $c = $ls->{by_role}{$r} || 0;
        push @role_lines, "$r=$c" if $c;
    }
    if (@role_lines) {
        print "  Roles: " . join(', ', @role_lines) . "\n";
    }

    if (@{ $ls->{entries} || [] }) {
        print "  Entry-point-like files:\n";
        for my $p (@{ $ls->{entries} }) {
            print "    - $p\n";
        }
    }

    if (@{ $ls->{configs} || [] }) {
        print "  Config / manifest files:\n";
        for my $p (@{ $ls->{configs} }) {
            print "    - $p\n";
        }
    }

    print "\n";
}

# ------------------------------------------------------------
# REPO TREE
# ------------------------------------------------------------

print "### REPO TREE\n\n";
for my $p (@paths) {
    my @parts  = split m{/}, $p;
    my $indent = '  ' x (@parts - 1);
    my $name   = $parts[-1];
    my $slash  = $is_dir{$p} ? '/' : '';
    print "$indent$name$slash\n";
}

print "\n### FILE CONTENTS\n";
print "# Each file is wrapped in markers and code fences for LLM consumption.\n";
print "# Fences use the form ```lang:path/to/file for easy mapping.\n\n";

# ------------------------------------------------------------
# FILE CONTENTS
# ------------------------------------------------------------

my $use_chunks = $MAX_LINES && $MAX_LINES > 0;

for my $rel (@files) {
    my $fi = $file_info{$rel} or next;
    my $full      = $fi->{full};
    my $size      = $fi->{size};
    my $is_text   = $fi->{is_text};
    my $lang_id   = $fi->{lang_id};
    my $lang_name = $fi->{lang_name};
    my $category  = $fi->{category};

    my $role_text = $category eq 'source' ? 'source code'
                   : $category eq 'test'   ? 'tests'
                   : $category eq 'config' ? 'configuration / manifest'
                   : $category eq 'docs'   ? 'documentation'
                   :                         'other';

    my $hint = role_hint($category, $fi->{lang_key}, $rel, $fi->{is_config}, $fi->{is_entry});

    print "\n=== FILE START: $rel ===\n";
    print "Size: $size bytes | Text: " . ($is_text ? 'yes' : 'no') . "\n";
    print "Language: $lang_name ($lang_id) | Role: $role_text\n";
    print "Hints: $hint\n" if $hint;
    print "Chunks: " . ($use_chunks ? "up to $MAX_LINES lines per chunk" : 'single chunk') . "\n";

    if (!$is_text) {
        print "[[ BINARY OR NON-TEXT FILE – CONTENT OMITTED ]]\n";
        print "=== FILE END: $rel ===\n";
        next;
    }

    if ($size > $MAX_BYTES) {
        print "[[ FILE TOO LARGE (> $MAX_BYTES bytes). CONTENT OMITTED. ]]\n";
        print "=== FILE END: $rel ===\n";
        next;
    }

    my $fh;
    unless (open $fh, '<', $full) {
        print "[[ ERROR: cannot open file ]]\n";
        print "=== FILE END: $rel ===\n";
        next;
    }

    my $chunk         = 1;
    my $line_in_chunk = 0;
    my $line_in_file  = 0;

    my $fence_lang = $lang_id;
    $fence_lang =~ s/\s+/_/g;

    my $info = $fence_lang ? "$fence_lang:$rel" : $rel;

    print "\n";
    print "--- CHUNK $chunk of $rel ---\n" if $use_chunks;
    print "```$info\n";

    while (my $l = <$fh>) {
        $line_in_file++;

        if ($use_chunks) {
            $line_in_chunk++;
            if ($line_in_chunk > $MAX_LINES) {
                print "```\n\n";
                $chunk++;
                $line_in_chunk = 1;
                print "--- CHUNK $chunk of $rel ---\n";
                print "```$info\n";
            }
        }

        if ($LINE_NUMS) {
            printf "%5d| %s", $line_in_file, $l;
        } else {
            print $l;
        }
    }

    close $fh;
    print "```\n";
    print "=== FILE END: $rel ===\n";
}
