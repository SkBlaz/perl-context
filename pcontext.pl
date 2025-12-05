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
# ------------------------------------------------------------

our $tmp_root;

sub clone_git_repo {
    my ($git_url) = @_;
    $tmp_root = tempdir( "pcontext-XXXXXX", CLEANUP => 0 );
    my $target = "$tmp_root/repo";

    print "# Cloning $git_url into $target\n";
    my $rc = system( 'git', 'clone', '--depth', '1', $git_url, $target );
    if ( $rc != 0 ) {
        die "git clone failed with exit code " . ( $rc >> 8 ) . "\n";
    }

    return abs_path($target);
}

# Register cleanup for the temp directory
END {
    if ( defined $tmp_root && -d $tmp_root ) {
        remove_tree( $tmp_root, { error => \my $err } );

        # ignore errors; this is best-effort cleanup
    }
}

sub process_command_line_args {
    my $git_url  = undef;
    my $help     = 0;
    my $compress = 0;

    GetOptions(
        'git_url=s' => \$git_url,
        'help'      => \$help,
        'compress'  => \$compress,
    ) or die "Usage: $0 [--git_url URL] [--compress] [path]\n";

    if ($help) {
        print "Usage:\n";
        print "  $0 [--git_url URL] [--compress] [path]\n\n";
        print "Options:\n";
        print "  --git_url URL   Clone a Git repository from URL\n";
        print
"  --compress      Output compressed mode (structure only, no file contents)\n";
        print "  --help          Show this help message\n\n";
        print "Examples:\n";
        print "  $0 .\n";
        print "  $0 /path/to/repo\n";
        print "  $0 --git_url https://github.com/SkBlaz/py3plex.git\n";
        print "  $0 --compress .\n";
        exit 0;
    }

    my $path;
    if ($git_url) {
        $path = clone_git_repo($git_url);
    }
    else {
        $path = shift @ARGV // '.';
        $path = abs_path($path);
    }

    # Returns (path, compress_flag)
    return ( $path, $compress );
}

# ------------------------------------------------------------
# Language mapping
# ------------------------------------------------------------

my %ext_to_lang = (
    pl       => 'perl',
    pm       => 'perl',
    py       => 'python',
    rb       => 'ruby',
    js       => 'javascript',
    mjs      => 'javascript',
    cjs      => 'javascript',
    ts       => 'typescript',
    tsx      => 'tsx',
    jsx      => 'jsx',
    java     => 'java',
    c        => 'c',
    h        => 'c',
    cpp      => 'cpp',
    cc       => 'cpp',
    cxx      => 'cpp',
    hh       => 'cpp',
    hpp      => 'cpp',
    go       => 'go',
    rs       => 'rust',
    php      => 'php',
    cs       => 'csharp',
    sh       => 'bash',
    zsh      => 'zsh',
    md       => 'markdown',
    markdown => 'markdown',
    json     => 'json',
    yml      => 'yaml',
    yaml     => 'yaml',
    html     => 'html',
    htm      => 'html',
    css      => 'css',
    sql      => 'sql',
    kt       => 'kotlin',
    swift    => 'swift',
    r        => 'r',
    hs       => 'haskell',
    toml     => 'toml',
);

my %lang_name = (
    perl       => 'Perl',
    python     => 'Python',
    ruby       => 'Ruby',
    javascript => 'JavaScript',
    typescript => 'TypeScript',
    tsx        => 'TypeScript (TSX)',
    jsx        => 'JavaScript (JSX)',
    java       => 'Java',
    c          => 'C / headers',
    cpp        => 'C++',
    go         => 'Go',
    rust       => 'Rust',
    php        => 'PHP',
    csharp     => 'C#',
    bash       => 'Shell (bash)',
    zsh        => 'Shell (zsh)',
    markdown   => 'Markdown',
    json       => 'JSON',
    yaml       => 'YAML',
    html       => 'HTML',
    css        => 'CSS',
    sql        => 'SQL',
    kotlin     => 'Kotlin',
    swift      => 'Swift',
    r          => 'R',
    haskell    => 'Haskell',
    toml       => 'TOML',
    text       => 'Text / other',
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
    return if not $pat or $pat =~ /^#/;
    return if $pat             =~ s/^!//;    # ignore negated

    my $re = quotemeta($pat);
    $re =~ s{/\\*\\*$}{/.*}g;                # /** at end
    $re =~ s{\\\*\\\*}{.*}g;                 # **
    $re =~ s{\\\*}{[^/]*}g;                  # *
    $re =~ s{\\\?}{[^/]}g;                   # ?

    if ( substr( $pat, 0, 1 ) eq '/' ) {

        # starts with / -> from root
        return qr{^$re};
    }
    else {
        # no slashes or slashes but not at start -> match after any slash
        return qr{(?:^|/)$re};
    }
}

sub build_ignore_list {
    my ( $root, $exclude_pat ) = @_;
    my @ignore_re;
    my $gitignore = "$root/.gitignore";

    if ( -f $gitignore && open my $gi, '<', $gitignore ) {
        while ( my $pat = <$gi> ) {
            chomp $pat;
            my $re = glob_to_regex($pat);
            push @ignore_re, $re if $re;
        }
        close $gi;
    }

    if ( length $exclude_pat ) {
        for my $pat ( split /\s*,\s*/, $exclude_pat ) {
            my $re = glob_to_regex($pat);
            push @ignore_re, $re if $re;
        }
    }
    return @ignore_re;
}

sub ignored {
    my ( $rel, $ignore_re ) = @_;
    for my $re (@$ignore_re) {
        return 1 if $rel =~ $re;
    }
    return 0;
}

# ------------------------------------------------------------
# Role & hint classification
# ------------------------------------------------------------

sub file_role_and_flags {
    my ( $rel, $ext, $lang_key ) = @_;
    my $lc = lc $rel;
    my $category;
    my $is_config = 0;
    my $is_entry  = 0;

    # Entrypoints by language
    if ( $lang_key && $lang_key eq 'python' ) {
        $is_entry = 1 if $lc =~ m{(^|/)(main|app|wsgi|asgi|manage)\.py$};
    }
    elsif (
        $lang_key
        && (   $lang_key eq 'javascript'
            || $lang_key eq 'typescript'
            || $lang_key eq 'tsx'
            || $lang_key eq 'jsx' )
      )
    {
        $is_entry = 1
          if $lc =~
          m{(^|/)(src/)?(index|main|app|server|cli)\.(js|jsx|ts|tsx)$};
    }
    elsif ( $lang_key && $lang_key eq 'go' ) {
        $is_entry = 1
          if $lc =~ m{(^|/)cmd/[^/]+/main\.go$} || $lc =~ m{(^|/)main\.go$};
    }
    elsif ( $lang_key && $lang_key eq 'rust' ) {
        $is_entry = 1
          if $lc =~ m{(^|/)src/main\.rs$} || $lc =~ m{(^|/)src/bin/[^/]+\.rs$};
    }
    elsif ( $lang_key && $lang_key eq 'java' ) {
        $is_entry = 1
          if $lc =~ m{(^|/)src/main/java/.+/(Main|Application)\.java$};
    }

    # Tests
    if (   $lc =~ m{(^|/)(test|tests|spec|__tests__)/}
        || $lc =~ m{(^|/)test_}
        || $lc =~ m{_test\.[a-z0-9_]+$}
        || $lc =~ m{\.spec\.[a-z0-9_]+$}
        || $lc =~ m{\.test\.[a-z0-9_]+$} )
    {
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
        if ( index( $lc, "/$pat" ) >= 0
            || substr( $lc, -length($pat) ) eq $pat )
        {
            $category  = 'config' unless defined $category;
            $is_config = 1;
            last;
        }
    }

    # Docs
    if (   !defined $category
        && $lc  =~ m{(^|/)(docs?|doc/)}
        && $ext =~ /^(md|rst|txt)$/i )
    {
        $category = 'docs';
    }
    if ( !defined $category
        && $lc =~ m{(^|/)(readme|changelog|license|copying)(\.|$)} )
    {
        $category = 'docs';
    }

    # Fallback
    if ( !defined $category ) {
        if ( defined $lang_key && $lang_key ne '' && $ext !~ /^(md|txt|rst)$/i )
        {
            $category = 'source';
        }
        else {
            $category = 'other';
        }
    }

    return ( $category, $is_config, $is_entry );
}

sub role_hint {
    my ( $category, $lang_key, $rel, $is_config, $is_entry ) = @_;
    my @bits;

    push @bits, 'probable application entrypoint' if $is_entry;

    if ( $category eq 'test' ) {
        if ( $lang_key && $lang_key eq 'python' ) {
            push @bits, 'Python tests (pytest/unittest style naming)';
        }
        elsif (
            $lang_key
            && (   $lang_key eq 'javascript'
                || $lang_key eq 'typescript'
                || $lang_key eq 'tsx'
                || $lang_key eq 'jsx' )
          )
        {
            push @bits, 'JS/TS tests (Jest/Vitest/Mocha style naming)';
        }
        elsif ( $lang_key && $lang_key eq 'go' ) {
            push @bits, 'Go tests (*_test.go)';
        }
        elsif ( $lang_key && $lang_key eq 'rust' ) {
            push @bits, 'Rust tests (unit/integration style)';
        }
        else {
            push @bits, 'Test code';
        }
    }

    if ( $category eq 'docs' ) {
        push @bits, 'Documentation / README-style content';
    }

    if ( $category eq 'config' && $is_config ) {
        if ( $rel =~ /package\.json$/i ) {
            push @bits, 'Node.js package manifest (dependencies + scripts)';
        }
        elsif ( $rel =~ /pyproject\.toml$/i ) {
            push @bits, 'Python project configuration (PEP 621 / tooling)';
        }
        elsif ( $rel =~ /requirements\.txt$/i ) {
            push @bits, 'Python dependencies list';
        }
        elsif ( $rel =~ /Cargo\.toml$/i ) { push @bits, 'Rust crate manifest'; }
        elsif ( $rel =~ /go\.mod$/i ) { push @bits, 'Go module definition'; }
        elsif ( $rel =~ /pom\.xml$/i ) {
            push @bits, 'Maven build configuration';
        }
    }

    return @bits ? join( ', ', @bits ) : '';
}

# ------------------------------------------------------------
# Config
# ------------------------------------------------------------

sub get_config {
    my ($compress) = @_;
    my $MAX_BYTES = $ENV{REPO_DUMP_MAX_BYTES} || 300_000;
    my $MAX_LINES =
      defined $ENV{REPO_DUMP_MAX_LINES}
      ? $ENV{REPO_DUMP_MAX_LINES}
      : 1200;
    my $LINE_NUMS   = $ENV{REPO_DUMP_LINE_NUMBERS} ? 1 : 0;
    my $ONLY_EXTS   = $ENV{REPO_DUMP_ONLY_EXT} || '';
    my $EXCLUDE_PAT = $ENV{REPO_DUMP_EXCLUDE}  || '';

    my %only_ext;
    if ( length $ONLY_EXTS ) {
        %only_ext = map { lc($_) => 1 }
          grep { length } split /\s*,\s*/, $ONLY_EXTS;
    }

    return {
        max_bytes   => $MAX_BYTES,
        max_lines   => $MAX_LINES,
        line_nums   => $LINE_NUMS,
        only_ext    => \%only_ext,
        exclude_pat => $EXCLUDE_PAT,
        compress    => $compress || 0,
    };
}

# ------------------------------------------------------------
# Walk repo
# ------------------------------------------------------------

sub walk_repo {
    my ( $root, $config, $ignore_re ) = @_;

    my @paths;
    my @files;
    my %is_dir;

    find(
        {
            no_chdir => 1,
            wanted   => sub {
                my $path = $File::Find::name;
                return if $path eq $root;

                if ( -d _ ) {
                    my ($name) = $path =~ m{([^/]+)$};
                    if (   $name =~ /^\.(git|svn|hg)$/
                        || $name =~
                        /^(node_modules|dist|build|target|venv|__pycache__)$/ )
                    {
                        $File::Find::prune = 1;
                        return;
                    }
                }

                my $rel = File::Spec->abs2rel( $path, $root );
                return if ignored( $rel, $ignore_re );

                push @paths, $rel;
                if ( -d _ ) {
                    $is_dir{$rel} = 1;
                }
                elsif ( -f _ ) {
                    if ( %{ $config->{only_ext} } ) {
                        my ($ext) = $rel =~ /\.([A-Za-z0-9_]+)$/;
                        my $lang_ext = lc( $ext // '' );
                        return if !$lang_ext || !$config->{only_ext}{$lang_ext};
                    }
                    push @files, $rel;
                }
            },
        },
        $root
    );

    @paths = sort @paths;
    @files = sort @files;

    return ( \@paths, \@files, \%is_dir );
}

# ------------------------------------------------------------
# Stats and metadata
# ------------------------------------------------------------

sub collect_stats {
    my ( $paths_ref, $files_ref, $is_dir_ref, $root ) = @_;

    my %file_info;
    my %lang_stats;
    my %ext_count;
    my $total_bytes = 0;
    my $dir_count   = 0;

    for my $p (@$paths_ref) {
        $dir_count++ if $is_dir_ref->{$p};
    }

    for my $rel (@$files_ref) {
        my $full    = "$root/$rel";
        my $size    = -s $full // 0;
        my $is_text = -T $full;

        $total_bytes += $size;

        my ($ext) = $rel =~ /\.([A-Za-z0-9_]+)$/;
        my $lang_ext = lc( $ext // '' );
        $ext_count{$lang_ext}++ if $lang_ext;

        my $lang_key  = $ext_to_lang{$lang_ext} || '';
        my $lang_id   = $lang_key || ( $lang_ext || 'text' );
        my $lang_name = lang_display_name( $lang_key || 'text' );

        my ( $category, $is_config, $is_entry ) =
          file_role_and_flags( $rel, $lang_ext, $lang_key );

        $file_info{$rel} = {
            full      => $full,
            size      => $size,
            is_text   => $is_text,
            ext       => $lang_ext,
            lang_key  => $lang_key,
            lang_id   => $lang_id,
            lang_name => $lang_name,
            category  => $category,
            is_config => $is_config,
            is_entry  => $is_entry,
        };

        my $lang_stats_ref = $lang_stats{$lang_id} ||= {
            name    => $lang_name,
            count   => 0,
            bytes   => 0,
            by_role => {},
            entries => [],
            configs => [],
        };

        $lang_stats_ref->{count}++;
        $lang_stats_ref->{bytes} += $size;
        $lang_stats_ref->{by_role}{$category}++;
        push @{ $lang_stats_ref->{entries} }, $rel if $is_entry;
        push @{ $lang_stats_ref->{configs} }, $rel if $is_config;
    }
    return ( \%file_info, \%lang_stats, \%ext_count, $total_bytes, $dir_count );
}

# ------------------------------------------------------------
# Select key files
# ------------------------------------------------------------

sub select_key_files {
    my ( $files_ref, $file_info_ref ) = @_;
    my @key_files;
    for my $rel (@$files_ref) {
        my $current_file_info_ref = $file_info_ref->{$rel} or next;
        my $cat                   = $current_file_info_ref->{category};
        if (   $cat eq 'docs'
            || $current_file_info_ref->{is_entry}
            || $current_file_info_ref->{is_config} )
        {
            push @key_files, $rel;
        }
    }
    return @key_files;
}

# ------------------------------------------------------------
# REPO OVERVIEW
# ------------------------------------------------------------

sub generate_repo_overview {
    my ( $root, $dir_count, $file_count, $total_bytes, $key_files_ref,
        $file_info_ref, $ext_count_ref )
      = @_;

    my $approx_tokens = int( ( $total_bytes || 0 ) / 4 ) || 0;

    print "### REPO OVERVIEW\n\n";
    print "Root: $root\n";
    print "Dirs: $dir_count\n";
    print "Files (included by filters): $file_count\n";
    print "Approx total bytes (sum of file sizes): $total_bytes\n";
    print "Approx tokens (~4 chars/token): $approx_tokens\n\n";

    if (@$key_files_ref) {
        print
"Key docs / entrypoints / configs (good starting points for the LLM):\n";
        for my $kf ( sort @$key_files_ref ) {
            my $current_file_info_ref = $file_info_ref->{$kf};
            my $tag                   = $current_file_info_ref->{category};
            $tag .= ", entrypoint-ish" if $current_file_info_ref->{is_entry};
            $tag .= ", config"         if $current_file_info_ref->{is_config};
            print "- $kf [$tag]\n";
        }
        print "\n";
    }

    if (%$ext_count_ref) {
        print "By extension (raw counts):\n";
        for my $e (
            sort { $ext_count_ref->{$b} <=> $ext_count_ref->{$a} || $a cmp $b }
            keys %$ext_count_ref
          )
        {
            print "- $e: $ext_count_ref->{$e}\n";
        }
        print "\n";
    }
}

# ------------------------------------------------------------
# LANGUAGE OVERVIEW
# ------------------------------------------------------------

sub generate_language_overview {
    my ($lang_stats_ref) = @_;

    print "### LANGUAGE OVERVIEW\n\n";

    for my $lang_id (
        sort {
            ( $lang_stats_ref->{$b}{bytes} <=> $lang_stats_ref->{$a}{bytes} )
              || (
                $lang_stats_ref->{$b}{count} <=> $lang_stats_ref->{$a}{count} )
              || ( $lang_stats_ref->{$a}{name} cmp $lang_stats_ref->{$b}{name} )
        } keys %$lang_stats_ref
      )
    {
        my $current_lang_stats_ref = $lang_stats_ref->{$lang_id};
        my $tokens = int( ( $current_lang_stats_ref->{bytes} || 0 ) / 4 );

        print
"- $current_lang_stats_ref->{name} ($lang_id): $current_lang_stats_ref->{count} files, ~$tokens tokens\n";

        my @roles = qw(source test config docs other);
        my @role_lines;
        for my $r (@roles) {
            my $c = $current_lang_stats_ref->{by_role}{$r} || 0;
            push @role_lines, "$r=$c" if $c;
        }
        if (@role_lines) {
            print "  Roles: " . join( ', ', @role_lines ) . "\n";
        }

        if ( @{ $current_lang_stats_ref->{entries} || [] } ) {
            print "  Entry-point-like files:\n";
            for my $p ( @{ $current_lang_stats_ref->{entries} } ) {
                print "    - $p\n";
            }
        }

        if ( @{ $current_lang_stats_ref->{configs} || [] } ) {
            print "  Config / manifest files:\n";
            for my $p ( @{ $current_lang_stats_ref->{configs} } ) {
                print "    - $p\n";
            }
        }

        print "\n";
    }
}

# ------------------------------------------------------------
# REPO TREE
# ------------------------------------------------------------

sub generate_repo_tree {
    my ( $paths_ref, $is_dir_ref ) = @_;

    print "### REPO TREE\n\n";
    for my $p (@$paths_ref) {
        my @parts  = split m{/}, $p;
        my $indent = '  ' x ( @parts - 1 );
        my $name   = $parts[-1];
        my $slash  = $is_dir_ref->{$p} ? '/' : '';
        print "$indent$name$slash\n";
    }
}

# ------------------------------------------------------------
# FILE CONTENTS
# ------------------------------------------------------------

sub category_to_role_text {
    my ( $category, $verbose ) = @_;
    $verbose ||= 0;

    if ($verbose) {
        return
            $category eq 'source' ? 'source code'
          : $category eq 'test'   ? 'tests'
          : $category eq 'config' ? 'configuration / manifest'
          : $category eq 'docs'   ? 'documentation'
          :                         'other';
    }
    else {
        return
            $category eq 'source' ? 'source'
          : $category eq 'test'   ? 'test'
          : $category eq 'config' ? 'config'
          : $category eq 'docs'   ? 'docs'
          :                         'other';
    }
}

sub dump_file_contents {
    my ( $files_ref, $file_info_ref, $config ) = @_;

    if ( $config->{compress} ) {
        print "\n### FILE LIST\n";
        print "# Compressed mode: showing file metadata only (no contents).\n";
        print
"# Use without --compress to see full file contents in code fences.\n\n";

        for my $rel (@$files_ref) {
            my $current_file_info_ref = $file_info_ref->{$rel} or next;
            my $size                  = $current_file_info_ref->{size};
            my $is_text               = $current_file_info_ref->{is_text};
            my $lang_name             = $current_file_info_ref->{lang_name};
            my $category              = $current_file_info_ref->{category};

            my $role_text      = category_to_role_text( $category, 0 );
            my $text_indicator = $is_text ? 'text' : 'binary';
            print
              "- $rel [$lang_name, $role_text, $size bytes, $text_indicator]\n";
        }
        return;
    }

    print "\n### FILE CONTENTS\n";
    print
"# Each file is wrapped in markers and code fences for LLM consumption.\n";
    print "# Fences use the form ```lang:path/to/file for easy mapping.\n\n";

    my $use_chunks = $config->{max_lines} && $config->{max_lines} > 0;

    for my $rel (@$files_ref) {
        my $current_file_info_ref = $file_info_ref->{$rel} or next;
        my $full                  = $current_file_info_ref->{full};
        my $size                  = $current_file_info_ref->{size};
        my $is_text               = $current_file_info_ref->{is_text};
        my $lang_id               = $current_file_info_ref->{lang_id};
        my $lang_name             = $current_file_info_ref->{lang_name};
        my $category              = $current_file_info_ref->{category};

        my $role_text = category_to_role_text( $category, 1 );

        my $hint = role_hint(
            $category, $current_file_info_ref->{lang_key},
            $rel,
            $current_file_info_ref->{is_config},
            $current_file_info_ref->{is_entry}
        );

        print "\n=== FILE START: $rel ===\n";
        print "Size: $size bytes | Text: " . ( $is_text ? 'yes' : 'no' ) . "\n";
        print "Language: $lang_name ($lang_id) | Role: $role_text\n";
        print "Hints: $hint\n" if $hint;
        print "Chunks: "
          . (
            $use_chunks
            ? "up to $config->{max_lines} lines per chunk"
            : 'single chunk'
          ) . "\n";

        if ( !$is_text ) {
            print "[[ BINARY OR NON-TEXT FILE – CONTENT OMITTED ]]\n";
            print "=== FILE END: $rel ===\n";
            next;
        }

        if ( $size > $config->{max_bytes} ) {
            print
"[[ FILE TOO LARGE (> $config->{max_bytes} bytes). CONTENT OMITTED. ]]\n";
            print "=== FILE END: $rel ===\n";
            next;
        }

        my $fh;
        unless ( open $fh, '<', $full ) {
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

        while ( my $l = <$fh> ) {
            $line_in_file++;

            if ($use_chunks) {
                $line_in_chunk++;
                if ( $line_in_chunk > $config->{max_lines} ) {
                    print "```\n\n";
                    $chunk++;
                    $line_in_chunk = 1;
                    print "--- CHUNK $chunk of $rel ---\n";
                    print "```$info\n";
                }
            }

            if ( $config->{line_nums} ) {
                printf "%5d| %s", $line_in_file, $l;
            }
            else {
                print $l;
            }
        }

        close $fh;
        print "```\n";
        print "=== FILE END: $rel ===\n";
    }
}

# ------------------------------------------------------------
# Main execution
# ------------------------------------------------------------

sub main {
    my ( $root, $compress ) = process_command_line_args();

    die "Error: Root path '$root' not found or is not a directory.\n"
      unless -d $root;

    print "# Starting analysis of $root\n";

    my $config = get_config($compress);

    my @ignore_re = build_ignore_list( $root, $config->{exclude_pat} );

    my ( $paths_ref, $files_ref, $is_dir_ref ) =
      walk_repo( $root, $config, \@ignore_re );
    my @paths  = @$paths_ref;
    my @files  = @$files_ref;
    my %is_dir = %$is_dir_ref;

    if ( !@files ) {
        print "# No files found in '$root' matching the criteria. Exiting.\n";
        return;
    }

    my (
        $file_info_ref, $lang_stats_ref, $ext_count_ref,
        $total_bytes,   $dir_count
    ) = collect_stats( \@paths, \@files, \%is_dir, $root );

    my @key_files = select_key_files( $files_ref, $file_info_ref );

    generate_repo_overview( $root, $dir_count, scalar(@files), $total_bytes,
        \@key_files, $file_info_ref, $ext_count_ref );
    generate_language_overview($lang_stats_ref);
    generate_repo_tree( \@paths, \%is_dir );
    dump_file_contents( \@files, $file_info_ref, $config );
}

main();

__END__
=head1 NAME

pcontext.pl - A script to dump repository or directory context for LLMs.

=head1 SYNOPSIS

    pcontext.pl [--git_url URL] [path]
    pcontext.pl --help

=head1 DESCRIPTION

This script is designed to provide a comprehensive overview of a software repository
for a Large Language Model (LLM). It can clone a Git repository or use a local
directory, then generates a detailed report including:

=over 4

=item *   A summary of the repository structure (directories, files).

=item *   Language statistics.

=item *   Key files like documentation, entrypoints, and configuration.

=item *   The full content of all included text files.

=back

The output is formatted with Markdown and special markers to be easily parsed by an LLM.

=head1 OPTIONS

=over 4

=item B<--git_url> I<URL>

Clones the specified Git repository into a temporary directory for analysis.
The C<--depth 1> flag is used for a shallow clone.

=item B<[path]>

The path to a local directory to analyze. If not provided, it defaults to the
current directory (C<.>). This is ignored if C<--git_url> is used.

=item B<--help>

Prints this help message and exits.

=back

=head1 ENVIRONMENT VARIABLES

The script's behavior can be customized with the following environment variables:

=over 4

=item B<REPO_DUMP_MAX_BYTES>

The maximum size of a single file in bytes to be included in the dump.
Defaults to C<300_000>.

=item B<REPO_DUMP_MAX_LINES>

The maximum number of lines per chunk when splitting large files. If set to C<0>,
files are not chunked. Defaults to C<1200>.

=item B<REPO_DUMP_LINE_NUMBERS>

If set to a non-zero value, each line in the file content will be prefixed
with its line number (e.g., C<"123| ">). Defaults to disabled.

=item B<REPO_DUMP_ONLY_EXT>

A comma-separated list of file extensions to include. If set, only files with
these extensions will be processed. The matching is case-insensitive.
Example: C<"py,ts,tsx">.

=item B<REPO_DUMP_EXCLUDE>

A comma-separated list of glob-like patterns to exclude from the analysis.
These are in addition to the patterns found in C<.gitignore>.

=back

=head1 EXAMPLES

=over 4

=item Dump the current directory:

    $ ./pcontext.pl .

=item Dump a specific local repository:

    $ ./pcontext.pl /path/to/my/project

=item Dump a remote repository from GitHub:

    $ ./pcontext.pl --git_url https://github.com/someuser/somerepo.git

=item Dump only Python and TypeScript files:

    $ REPO_DUMP_ONLY_EXT="py,ts" ./pcontext.pl .

=item Exclude additional patterns:

    $ REPO_DUMP_EXCLUDE="*.log,tmp/*" ./pcontext.pl .

=back

=head1 AUTHOR

This script was generated and improved by an AI assistant.

=cut
