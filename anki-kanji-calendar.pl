#!/usr/bin/env perl
use strict;
use warnings;
use Calendar::Calendar;
use POSIX 'strftime';
use Lingua::JA::Heisig 'kanji', 'heisig_number';
use DateTime;
use Lingua::JP::Kanjidic;
use Anki::Database;
use utf8::all;
my $dic = Lingua::JP::Kanjidic->new("$ENV{HOME}/.kanjidic");

my %kanji_for;
my %learned;
my $heisig_learned = 0;
my $total_learned = 0;
my $first_rtk1;
my $first_rtk3;
my %learned_type;
my ($min_ease, $max_ease) = (2.5, 2.5);

my $dbh = Anki::Database->new;
my $sth = $dbh->prepare("
    select facts.created, english.value, kanji.value, cards.factor, cards.yesCount, cards.noCount
    from cards
        join facts on (cards.factId = facts.id)
        join fields as english on (english.factId = facts.id)
        join fields as kanji on (kanji.factId = facts.id)
        join fieldModels as englishFM on (english.fieldModelId = englishFM.id)
        join fieldModels as kanjiFM on (kanji.fieldModelId = kanjiFM.id)
        join models on (facts.modelId = models.id)
        join cardModels on (cardModels.modelId = models.id)
    where
        models.name like '%漢字%'
        and englishFM.name = '英語'
        and kanjiFM.name = '漢字'
        and cardModels.name = '書け'
    group by kanji.value
    order by facts.created
;");
$sth->execute;

while (my ($date, $english, $kanji, $ease, $right, $wrong) = $sth->fetchrow_array) {
    my @lt = localtime($date);
    my $ym = strftime('%Y-%m', @lt);
    my $d  = $lt[3];

    $min_ease = $ease if $ease < $min_ease;
    $max_ease = $ease if $ease > $max_ease;

    ++$learned{$ym};
    ++$total_learned;
    my $heisig = heisig_number($kanji);
    if ($heisig) {
        ++$heisig_learned;
        if ($heisig_learned != $heisig) {
            warn "You seemed to learn $kanji out of order: It's your #$heisig_learned but Heisig's #$heisig";
        }
    }

    if ($heisig_learned == 1) {
        $first_rtk1 = DateTime->from_epoch(epoch => $date);
    }
    elsif ($heisig_learned == 3007) {
        $first_rtk3 = DateTime->from_epoch(epoch => $date);
    }

    push @{ $kanji_for{$ym}{$d} }, [$kanji, $english, $ease, $right, $wrong];
}

my @dates = sort keys %kanji_for;

$\ = "\n";

print <<'EOH';
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html>
  <head>
    <meta http-equiv="Content-Type" content="text/html;charset=utf-8" />
    <title>Kanji by Calvin Klein</title>
    <style type="text/css">
      table {
        border: 1px solid black;
        border-spacing: 0px;
        width: 80%;
        margin-left: auto;
        margin-right: auto;
      }
      td, th {
        border: 1px solid black;
        padding: .3em;
      }
      td {
        width: 14%;
        vertical-align: top;
      }
      td.nonday {
        background: #CCCCCC;
      }
      .date, h2 {
        text-align: center;
      }
      td.today {
        background: #EEEEFF;
        border: 1px solid #000055;
      }
      .kanji_group {
        font-size: 150%;
        letter-spacing: 5px;
      }
      .projected {
        filter:alpha(opacity=30);
        -moz-opacity: 0.3;
        -khtml-opacity: 0.3;
        opacity: 0.3;
      }
      hr {
        border: 0;
        margin-top: 2em;
        margin-bottom: 2em;
      }
    </style>
  <body>
    <p title="even this tip" style="font-size: small">(yo, everything has tooltips)</p>
    <p><a title="if you use it I'd like to see!" href="http://github.com/sartak/anki-kanji-calendar">peep the code</a></p>
EOH

my $i = 0;
my ($today_d, $today_m, $today_y) = (localtime)[3,4,5];
$today_y += 1900; ++$today_m;
my @months = (undef, qw/January February March April May June July August September October November December/);

while (@dates) {
    my $ym = shift @dates;
    my ($year, $month) = $ym =~ /^(\d{4})-0?(\d{1,2})/;
    my @cal = Calendar::Calendar::generic_calendar($month, $year);
    my $learned = $learned{$ym};

    print "    <h2 id=\"$ym\" title=\"Learned $learned\">$months[$month] $year</h2>";
    print "    <table>";
    print "      <tr><th>S</th><th>M</th><th>T</th><th>W</th><th>T</th><th>F</th><th>S</th></tr>";

    for my $week (@cal) {
        print "      <tr>";
        my @days = @$week;
        while (@days) {
            my $day = shift @days;
            if (defined($day)) {
                my $today = $day eq $today_d
                         && $month eq $today_m
                         && $year eq $today_y;

                print "<td" . ($today ? " class='today'" : "") . ">";
                my @kanji = @{ $kanji_for{$ym}{$day} || [] };

                my $learned_today = @kanji;
                $learned_today = $total_learned - $i
                    if $learned_today && $i + @kanji > $total_learned;

                print '<div class="date" title="Learned '.$learned_today.'">'.$day.'</div>';

                if ($today || @kanji) {
                    print '<span class="kanji_group">';
                    if ($today) {
                        # didn't finish for today
                        if (@kanji < 32) {
                            push @kanji,
                                map {
                                    my $meanings = join '/', @{$dic->lookup($_)->{meaning}};
                                    [
                                        $_,
                                        "$meanings (projected)"
                                    ]
                                }
                                split '',
                                substr(kanji(), $heisig_learned, 32 - @kanji);
                        }
                        # project for tomorrow, if it wouldn't add a new week
                        elsif ($days[0]) {
                            $kanji_for{$ym}{$days[0]} = [
                                map { [$_, '(projected)'] }
                                split '',
                                substr(kanji(), $heisig_learned, 32)
                            ];
                        }
                    }

                    print join '',
                        map {
                            ++$i;
                            my ($kanji, $meaning, $ease, $right, $wrong) = @$_;
                            $meaning =~ s/'/&#39;/g;
                            $ease ||= 2.5; $right ||= 0; $wrong ||= 0;
                            my $total = $right + $wrong;
                            my $ratio = $total ? sprintf '%i%% %i/%i', int(100 * $right / $total), $right, $total : 'untested';
                            my $heisig = heisig_number($kanji);
                            my $type = $heisig && $heisig <= 2042 ? 'RTK1'
                                     : $heisig && $heisig > 2042  ? 'RTK3'
                                                                  : 'NH';
                            $type .= ' ' . ++$learned_type{$type};

                            my $color = '000000';
                            if ($ease <= 2.5) {
                                $color = sprintf '%x0000', int(256*(2.5-$ease)/(2.5-$min_ease));
                            }
                            else {
                                $color = sprintf '00%x00', int(256*($ease-2.5)/($max_ease-2.5));

                            }

                            "<span class='kanji".
                            ($i > $total_learned ? " projected" : "").
                            "' title='#$i $meaning".
                            ($i > $total_learned ? '' : " ($ratio)").
                            " ($type)".
                            "' style='color:#$color'".
                            ">$kanji</span>"
                        }
                        @kanji;

                    print '</span>';
                }
                else {
                    print "<br />";
                }
            }
            else {
                print "        <td class='nonday'>";
                print '<div></div>';
            }
            print "        </td>";
        }
        print "      </tr>";
    }

    print "    </table>";
    print "<hr />" if @dates;
}

print "<h2 id=\"predictions\">Crystal ball time</h2><ul>" if $heisig_learned < 3007;

my $today = DateTime->today;
my $tomorrow = $today->clone->add(days => 1);
my $begin = $today->clone->subtract(days => 30);
my $last_month = 0;
for (my $cur = $begin->clone; $cur < $tomorrow; $cur->add(days => 1)) {
    my $ym = $cur->year . '-' . $cur->month;
    $ym =~ s/-(\d)$/-0$1/;
    my $d = $cur->day;
    $last_month += @{ $kanji_for{$ym}{$d} || [] };
}
my $each_day = $last_month / 30;
my $each_day_display = sprintf '%.1f', $each_day;

my $remaining = 2042 - $heisig_learned;
my $completion_date = DateTime->today->subtract(days => 1);
if ($remaining > 0) {
    my $r = $remaining;

    while ($r >= 1) {
        $completion_date->add(days => 1);
        $r -= $each_day;
    }

    my $completion = $completion_date->ymd;
    my $remaining_days = $completion_date->delta_days(DateTime->today)->delta_days;
    my $total_days = $completion_date->delta_days($first_rtk1)->delta_days;
    my $total_months = sprintf '%.1f', $total_days / 30;
    my $percent = int(100 * $remaining / 2042);

    print "<li><b>$remaining</b>/2042 ($percent%) RTK1 kanji remain, estimated completion <b>$completion</b> (<b>$remaining_days</b> more days), having taken a total of <b>$total_days</b> days (~<b>$total_months</b> months).</li>";
}

$heisig_learned -= 2042;
$heisig_learned = 0 if $heisig_learned < 0;
$remaining = (3007 - 2042) - $heisig_learned;
if ($remaining > 0) {
    my $r = $remaining;

    my $today_rtk3;

    if (!$first_rtk3) {
        $first_rtk3 = $completion_date->clone;
        $today_rtk3 = $first_rtk3->clone;
    }
    else {
        $today_rtk3 = DateTime->today;
    }

    while ($r >= 1) {
        $completion_date->add(days => 1);
        $r -= $each_day;
    }

    my $completion = $completion_date->ymd;
    my $remaining_days = $completion_date->delta_days($today_rtk3)->delta_days;
    my $total_days = $completion_date->delta_days($first_rtk3)->delta_days;
    my $total_months = sprintf '%.1f', $total_days / 30;
    my $percent = int(100 * $remaining / 965);

    print "<li><b>$remaining</b>/965 ($percent%) RTK3 kanji remain, estimated completion <b>$completion</b> (<b>$remaining_days</b> more days), having taken a total of <b>$total_days</b> days (~<b>$total_months</b> months).</li>";
}

if ($remaining > 0) {
    print "<li>Predictions are based on last 30 days, which added <b>$last_month</b> kanji, ~<b>$each_day_display</b>/day.</li></ul>";
}

print <<'EOH';
  </body>
</html>
EOH
