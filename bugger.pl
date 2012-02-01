#!/usr/bin/perl -w

use strict;
use Glib ':constants';
use Gtk2;
use Gtk2::Helper;
use Gtk2::Pango; # pango constants
use Bugger::Lookup;

my $bugger = new Bugger::Lookup;

my %severity_map = (
	wishlist => undef,
	minor	=> undef,
	normal	=> undef,
	important => undef,
	serious => undef,
	grave => undef
);
	
Gtk2->init;

my $pid = -1;
my $window = Gtk2::Window->new ('toplevel');

$window->set_border_width(5);
$window->set_default_size(640, 480);
$window->set_title("Bugger!");

my $menu = new Gtk2::Menu();
my $menu_quit = new Gtk2::MenuItem('Quit');
$menu_quit->show();
$menu->append($menu_quit);

my $bugger_menu = new Gtk2::MenuItem('Bugger!');
$bugger_menu->set_submenu($menu);
$bugger_menu->show();

my $menubar = new Gtk2::MenuBar();
# Layout tree of this program
my $vbox = Gtk2::VBox->new;
	my $paned = Gtk2::VPaned->new;
		my $scwin = Gtk2::ScrolledWindow->new;
			my $tv = Gtk2::TreeView->new;
			my $model = Gtk2::TreeStore->new ('Glib::String', 'Glib::String', 'Glib::String', 'Glib::String', 'Glib::Boolean');
		my $scwin_message = Gtk2::ScrolledWindow->new;
			my $textview = Gtk2::TextView->new;
				my $tvbuf = $textview->get_buffer();
				my $font_tag = $tvbuf->create_tag('font', 'font', 'monospace 9');
				my $bold_tag = $tvbuf->create_tag("bold", 'font' => 'monospace 9', 'weight' => PANGO_WEIGHT_BOLD);
	my $bottom_hbox = Gtk2::HBox->new;
		my $bnlabel = Gtk2::Label->new('Bug number:');
		my $bugnumber = Gtk2::Entry->new;
		my $pkglabel = Gtk2::Label->new('Source package:');
		my $srcpkg = Gtk2::Entry->new;
		
# end layout tree

$scwin->add($tv);
$scwin_message->add($textview);
$scwin->set_policy('automatic', 'automatic');
$scwin_message->set_policy('automatic', 'automatic');

$paned->add1($scwin);

$vbox->pack_start ($menubar, 0, 0, 0);
# This menu stuff will be cleaned up
$menubar->show();
$menubar->append($bugger_menu);
$paned->add2($scwin_message);

$vbox->pack_start($paned, TRUE, TRUE, 0);
$vbox->pack_start($bottom_hbox, FALSE, TRUE, 0);

$paned->set_position(200);

$bottom_hbox->pack_start($bnlabel, TRUE, TRUE, 0);
$bottom_hbox->pack_start($bugnumber, TRUE, TRUE, 0);
$bottom_hbox->pack_start($pkglabel, TRUE, TRUE, 0);
$bottom_hbox->pack_start($srcpkg, TRUE, TRUE, 0);

$textview->set_editable(FALSE);

$window->add($vbox);

$tv->set_model($model);

$tv->append_column
	(Gtk2::TreeViewColumn->new_with_attributes
		("Severity / Bug#", Gtk2::CellRendererText->new, text => 0));
$tv->append_column
	(Gtk2::TreeViewColumn->new_with_attributes
		("Tags", Gtk2::CellRendererText->new, text => 1));
$tv->append_column
	(Gtk2::TreeViewColumn->new_with_attributes
		("Title", Gtk2::CellRendererText->new, text => 2));
$tv->append_column
	(Gtk2::TreeViewColumn->new_with_attributes
		("Submitter", Gtk2::CellRendererText->new, text => 3));

$menu_quit->signal_connect(activate => sub {Gtk2->main_quit;});
$window->signal_connect(delete_event => sub {Gtk2->main_quit;});

my %sevs;
my %parentbugs;
my %display_as_merged;

# Allow multiple selections 
# TODO: Get this working
#$tv->get_selection->set_mode('extended');

$bugnumber->signal_connect('activate' => sub {
	my $bn = $bugnumber->get_text;
	if ($bn =~ /^[1-9][0-9]*$/) {
		$window->set_title("Bugger! [bug: $bn -- Querying BTS]");
		$bugnumber->set_sensitive(FALSE);
		Gtk2->main_iteration while Gtk2->events_pending;
		fill($bugger->get($bn));
		$window->set_title("Bugger!");
		$bugnumber->set_sensitive(TRUE);
	}
});
	

# TODO: This sub needs moved to Bugger::UI when that change occurs
$tv->signal_connect('row-activated' => sub {
	my $iter = $tv->get_selection->get_selected;
	my ($bn, $submitter) = $model->get($iter, 0, 2);
	if ($bn =~ /^[1-9][0-9]*$/) { fill($bugger->get($bn)) };
});

sub fill
{
	my $mbox = shift;
	
	$tvbuf->set_text("");
    
    foreach my $msg (@{$mbox}) {
		my $from = "From: " . $msg->{'from'} . "\n";
        my $subject = "Subject: " . $msg->{'subject'} . "\n\n";
		$tvbuf->insert_with_tags($tvbuf->get_end_iter, $from, $bold_tag);
		$tvbuf->insert_with_tags($tvbuf->get_end_iter, $subject, , $bold_tag);
		$tvbuf->insert_with_tags($tvbuf->get_end_iter, $msg->{'body'} . "\n\n", $font_tag);
    }	
}

# Needs to be moved to Bugger::UI
$srcpkg->signal_connect(activate => sub { 
	my $package = $srcpkg->get_text;
	$window->set_title("Bugger! [package: $package -- Querying BTS]");
	$srcpkg->set_sensitive(0);
	# Right now Bugger::Lookup uses LWP which doesn't give a filehandle for a
	# watch, so we need to update the GUI events before blocking.
	Gtk2->main_iteration while Gtk2->events_pending;
	$model->clear();
	%severity_map = ();
	my @bug_list = $bugger->package($package);
	
	# Check if we have a parent for that severity, if not then create it and
	# store it in our severity map
	foreach (@bug_list) {
		if (!defined($severity_map{$_->{severity}})) {
			my $label = $_->{severity};
			$severity_map{$_->{severity}} = $model->append(undef);
			$model->set($severity_map{$_->{severity}}, 0, $label);
		}
		
		# Now store the bug in the TV with the correct parent
		my $bug_row = $model->append($severity_map{$_->{severity}});
		$model->set($bug_row, 0, $_->{number}, 1, $_->{tags}, 2, $_->{subject}, 3, $_->{submitter});
	}
	
	$window->set_title("Bugger! [package: $package]");
	$srcpkg->set_sensitive(1);
});

$window->show_all;

Gtk2->main;

# vim:ts=4:noet:ai
