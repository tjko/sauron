# lab.pm -- Sauron CGI interface plugin: training lab tasks
#
# Shows the tasks of the Sauron training lab (lab/tasks.<lang>.md) together
# with their state, as reported by lab/lab-check --json. See lab/README.md.
#
package Sauron::Plugins::lab;

require Exporter;
use CGI qw/:standard *table/;
use JSON::PP;
use Sauron::Sauron;
use strict;
use warnings;
use utf8;
use vars qw($VERSION @ISA @EXPORT);

$VERSION = '1.0';
@ISA = qw(Exporter);
@EXPORT = qw();

my %TEXT = (
  heading  => { en => 'Lab tasks', cs => 'Úkoly labu' },
  check    => { en => 'Check again', cs => 'Zkontrolovat znovu' },
  summary  => { en => '%d of %d tasks done', cs => 'Splněno %d z %d úkolů' },
  task     => { en => 'Task', cs => 'Úkol' },
  account  => { en => 'Account', cs => 'Účet' },
  state    => { en => 'State', cs => 'Stav' },
  done     => { en => 'done', cs => 'splněno' },
  todo     => { en => 'not done', cs => 'nesplněno' },
  failed   => { en => 'Checking the tasks failed', cs => 'Kontrola úkolů selhala' },
  details  => { en => 'Assignments', cs => 'Zadání' },
  points   => { en => '%d of %d checks passed', cs => 'splněno %d z %d bodů kontroly' },
  checks   => { en => 'Checks', cs => 'Kontrola' },
);

sub _t($$) { my ($key, $lang) = @_; return $TEXT{$key}{$lang}; }

sub _lang() {
  my $l = param('lang') // '';
  return $l if $l =~ /^(cs|en)$/;
  return (($ENV{HTTP_ACCEPT_LANGUAGE} // '') =~ /^\s*cs/i) ? 'cs' : 'en';
}

# run lab-check and return its decoded JSON report (or an error string)
sub _check($) {
  my ($lang) = @_;
  my $cmd = "$main::PROG_DIR/lab/lab-check";
  return "$cmd not found" unless -x $cmd;
  my $fh;
  open($fh, '-|', $cmd, '--json', "--lang=$lang") or return "$cmd: $!";
  my $out = do { local $/; <$fh> };
  close($fh);
  my $res = eval { JSON::PP->new->utf8->decode($out // '') };
  return $res if ref $res eq 'HASH';
  return "$cmd: " . ($@ || 'no output');
}

# task descriptions: (intro html, { ID => html })
sub _descriptions($) {
  my ($lang) = @_;
  my $file = "$main::PROG_DIR/lab/tasks.$lang.md";
  open(my $fh, '<:encoding(UTF-8)', $file) or return ('', {});
  my ($id, %sec) = ('');
  while (my $line = <$fh>) {
    next if $line =~ /^# /;               # document title
    if ($line =~ /^## (\S+)/) { $id = $1; next; }
    $sec{$id} .= $line;
  }
  close($fh);
  my $intro = _markdown(delete $sec{''} // '');
  $sec{$_} = _markdown($sec{$_}) for keys %sec;
  return ($intro, \%sec);
}

sub _inline($) {
  my $s = escapeHTML(shift);
  $s =~ s{`([^`]+)`}{<code>$1</code>}g;
  $s =~ s{\*\*([^*]+)\*\*}{<strong>$1</strong>}g;
  $s =~ s{(?<![\w*])\*([^*]+)\*(?![\w*])}{<em>$1</em>}g;
  return $s;
}

# minimal Markdown: paragraphs, "- " lists, tables, indented code blocks
sub _markdown($) {
  my ($text) = @_;
  my ($html, @block) = ('');
  my $flush = sub {
    return unless @block;
    if ($block[0] =~ /^    /) {
      $html .= '<pre>' . escapeHTML(join("\n", map { substr($_, 4) } @block)) . "</pre>\n";
    } elsif ($block[0] =~ /^\|/) {
      my @rows = grep { !/^\|[-| ]+\|$/ } @block;
      $html .= '<table class="s-list">';
      for my $i (0 .. $#rows) {
        my @c = split /\s*\|\s*/, $rows[$i];
        shift @c;
        my $tag = $i ? 'td' : 'th';
        $html .= ($i ? '<tr class="s-list__row">' : '<tr class="s-list__head">') .
                 join('', map { "<$tag>" . _inline($_) . "</$tag>" } @c) . '</tr>';
      }
      $html .= "</table>\n";
    } elsif ($block[0] =~ /^- /) {
      my @items;
      for (@block) {
        if (s/^- //) { push @items, $_ } else { s/^\s+//; $items[-1] .= " $_" }
      }
      $html .= '<ul>' . join('', map { '<li>' . _inline($_) . '</li>' } @items) . "</ul>\n";
    } else {
      $html .= '<p>' . _inline(join(' ', @block)) . "</p>\n";
    }
    @block = ();
  };
  for my $line (split /\n/, $text) {
    if ($line =~ /^\s*$/) { $flush->(); next; }
    # a code block or a list does not continue as a paragraph and vice versa
    # (an indented line in a "- " list continues the list item)
    $flush->() if @block && !($block[0] =~ /^- / && $line =~ /^\s/) &&
      (($line =~ /^    /) != ($block[0] =~ /^    /));
    push @block, $line;
  }
  $flush->();
  return $html;
}

sub menu_handler {
  my ($state, $perms) = @_;
  my $selfurl = $state->{selfurl};
  my $lang = _lang();
  my $url = "$selfurl?menu=hosts&sub=Pl_Lab";

  print '<div class="s-lab">',
        '<style>',
        '.s-lab .s-lab__ok{color:var(--s-success);font-weight:600}',
        '.s-lab .s-lab__todo{color:var(--s-danger);font-weight:600}',
        '.s-lab td{font-family:inherit}',
        '.s-lab .s-list .s-lab__row--ok>td{background:color-mix(in srgb,var(--s-success) 12%,var(--s-surface))}',
        '.s-lab .s-list .s-lab__row--todo>td{background:color-mix(in srgb,var(--s-danger) 8%,var(--s-surface))}',
        '.s-lab .s-lab__points{font-size:90%;color:var(--s-muted)}',
        '.s-lab .s-lab__task{margin-top:1em;padding:.25em 1em .5em;border-left:4px solid var(--s-border);border-radius:var(--s-radius)}',
        '.s-lab .s-lab__task--ok{border-left-color:var(--s-success);background:color-mix(in srgb,var(--s-success) 8%,var(--s-surface))}',
        '.s-lab .s-lab__task--todo{border-left-color:var(--s-danger);background:color-mix(in srgb,var(--s-danger) 5%,var(--s-surface))}',
        '.s-lab .s-lab__checks{list-style:none;padding-left:0}',
        '.s-lab .s-lab__checks li{margin:.15em 0}',
        '.s-lab .s-lab__detail{display:block;margin-left:1.4em;font-size:90%;color:var(--s-muted)}',
        '.s-lab pre{background:var(--s-border-subtle);padding:.5em;overflow-x:auto}',
        '</style>';

  print h2(_t('heading', $lang)),
        '<p>',
        a({-href => "$url&lang=$lang"}, _t('check', $lang)), ' &middot; ',
        ($lang eq 'cs' ? a({-href => "$url&lang=en"}, 'English') : 'English'), ' | ',
        ($lang eq 'en' ? a({-href => "$url&lang=cs"}, 'Česky') : 'Česky'),
        '</p>';

  my $res = _check($lang);
  my ($intro, $desc) = _descriptions($lang);
  my %state;

  if (!ref $res) {
    print '<div class="s-alert s-alert--error">', _t('failed', $lang), ': ',
          escapeHTML($res), '</div>';
  } else {
    my $all = ($res->{done} == $res->{total});
    printf '<div class="s-alert %s">%s</div>',
      ($all ? 's-alert--success' : 's-alert--info'),
      escapeHTML(sprintf(_t('summary', $lang), $res->{done}, $res->{total}));

    print '<table class="s-list">',
          '<tr class="s-list__head">', th(''), th(_t('task', $lang)),
          th(_t('account', $lang)), th(_t('state', $lang)), '</tr>';
    for my $t (@{$res->{tasks}}) {
      $state{$t->{id}} = $t;
      my @c = @{$t->{checks} // []};
      my $passed = grep { $_->{ok} } @c;
      my $points = @c ? '<br><a class="s-lab__points" href="#lab-' . escapeHTML($t->{id}) . '">' .
        escapeHTML(sprintf(_t('points', $lang), $passed, scalar @c)) . '</a>' : '';
      print '<tr class="s-list__row ', ($t->{ok} ? 's-lab__row--ok' : 's-lab__row--todo'), '">',
            td(a({-href => "#lab-$t->{id}"}, escapeHTML($t->{id}))),
            td(escapeHTML($t->{title}) . $points),
            td(escapeHTML($res->{accounts}{$t->{role}} || $t->{role})),
            td($t->{ok}
               ? '<span class="s-lab__ok">&#10003; ' . _t('done', $lang) . '</span>'
               : '<span class="s-lab__todo">&#10007; ' . _t('todo', $lang) . '</span>'),
            '</tr>';
    }
    print '</table>';
  }

  print h3(_t('details', $lang)), $intro;
  for my $id (ref $res ? map { $_->{id} } @{$res->{tasks}} : sort keys %$desc) {
    my $t = $state{$id};
    my $cls = $t ? ($t->{ok} ? ' s-lab__task--ok' : ' s-lab__task--todo') : '';
    print "<div class=\"s-lab__task$cls\" id=\"lab-", escapeHTML($id), "\">",
          h4(escapeHTML($id) . ' ' . escapeHTML($t ? $t->{title} : '') .
             ($t ? ($t->{ok} ? ' <span class="s-lab__ok">&#10003; ' . _t('done', $lang) . '</span>'
                             : ' <span class="s-lab__todo">&#10007; ' . _t('todo', $lang) . '</span>') : '')),
          ($desc->{$id} // '');
    if ($t && @{$t->{checks} // []}) {
      print '<p><strong>', _t('checks', $lang), ':</strong></p><ul class="s-lab__checks">';
      for my $c (@{$t->{checks}}) {
        print '<li>',
              ($c->{ok} ? '<span class="s-lab__ok">&#10003;</span> '
                        : '<span class="s-lab__todo">&#10007;</span> '),
              escapeHTML($c->{text}),
              (defined $c->{detail}
                 ? '<span class="s-lab__detail">' . escapeHTML($c->{detail}) . '</span>' : ''),
              '</li>';
      }
      print '</ul>';
    }
    print '</div>';
  }
  print '</div>';
}

1;
# eof
