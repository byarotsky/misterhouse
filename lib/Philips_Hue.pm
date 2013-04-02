=head1 B<Philips_Hue>

=head2 SYNOPSIS

Philips_Hue.pm - support for the Philips Hue devices

=head2 DESCRIPTION

This module adds support for Philis Hue lights to MisterHouse. More info on the hardware
can be found here:
  http://meethue.com
     
=head3 Usage

In your items.mht, add the Hue gateway and Hue devices like this:
 
   PHILIPS_HUE, <ipaddress_bridge>:<api_key>:<lamp_id>, kitchen_light, hue_gateway, Lights

e.g.:
   
   PHILIPS_HUE, 192.168.1.106:mytestusername:1, hue_1, Living
   
Then in your code do something like:
      
   # Switch on the light if it is getting dark
   if (<condition_that_needs_to_be_met>) {
     $kitchen_light>set('on');
   }

To control the brightness and the color of the lamp, use the ->bri(xx) and the ->ct_k(xx) or ->hs(xx,yy) functions.

E.g. to put the light in full brightness blue:
   $light->hs(46920,255);
   $light->bri(255);
   
=head3 Setup
 
This module communicates with the Hue lights through the bridge device. You need to detect 
the IP address of the bridge and you need to setup an API key to be able to access
the bridge from MisterHouse. 
Detect the IP address of your bridge with the C<hue-discover.pl> script that comes with 
Device::Hue. Follow the instructions presented in that script to setup an API key.

=head2 INHERITS

Generic_Item

=head2 METHODS

=over 

=item C<set>

Sets the state of the Hue light. Passing arguments C<on> or C<off> sets the light on or off. 
Note that C<on> restores the previous light state, both the color and the brightness.

=item C<effect>

Program an effect. This depends on what effects are supported by the firmware of the lamp.
Currently this command takes as parameters:

=over

=item C<colorloop>

Enable the color looping through all colors the lamp supports. Kids love it :-)

=item C<none>

Disable the active effect

=back
 
=item C<bri>

Control the brightness of a lamp in percentage. Supports values between 0 (off) and 100 (maximum)
brightness. Note that value '0' does not turn the lamp off, but sets it to minimal brightness.

=item C<ct_k>

Sets the color temperature in Kelvin. For 2012 lamps the value should be between 2000 K and 6500 K

=item C<hs>

Sets the hue/saturation values to determine the color of a lamp.
The hue value is a wrapping value between 0 and 65535. Both 0 and 65535 are red, 25500 is green and 46920 is blue.
For the saturation of the light, 255 is the most saturated (colored) and 0 is the least saturated (white).


=back

=head2 DEPENDENCIES:
 This code depends on the Perl module C<Device::Hue>. This module is published on CPAN.

=head2 AUTHOR
  Lieven Hollevoet  E<lt>lieven@lika.beE<gt>

=cut

use strict;

package Philips_Hue;

@Philips_Hue::ISA = ('Generic_Item');

use Device::Hue;

sub new {
    my ($class, $p_address) = @_;
    my ($gateway, $apikey, $lamp_id) = $p_address =~ /(\S+):(\S+):(\S+)/;
    my $self = $class->SUPER::new();
    $$self{gateway} = 'http://' . $gateway;
    $$self{apikey}  = $apikey;
    $$self{lamp_id} = $lamp_id;
    $$self{hue}     = new Device::Hue('bridge' => $$self{gateway}, 'key' => $$self{apikey}, 'debug' => 0);
    $$self{light}   = $$self{hue}->light($$self{lamp_id});
    
    $self->addStates ('on', 'off');
	
    return $self;
}


sub lamp_id {
    my ($self) = shift;
    return $$self{lamp_id};
}

sub addStates {
    my $self = shift;
    push(@{$$self{states}}, @_) unless $self->{displayonly};
}

sub default_setstate
{
    my ($self, $state, $substate, $set_by) = @_;
        
    my $cmnd = ($state =~ /^off/i) ? 'off' : 'on';
    	
    return -1 if ($self->state eq $state); # Don't propagate state unless it has changed.
    
    ::print_log('hue', "Request " . $self->get_object_name . " turn " . $cmnd);
	::print_log('hue', "Command settings: '" . $$self{gateway} . "' - '" . $$self{apikey} . "' - '" . $$self{lamp_id} . "' : '" . $cmnd. "'");
	
    # Disable the effect commands when we turn off the light
    if ($cmnd eq 'off') {
    	$self->effect('none');
    }
    
    $$self{light}->$cmnd;

	return;
	
}

sub effect
{
	my ($self, $effect) = @_;
	
	my $light_state = $self->state();
	
	::print_log('hue', "Effect '$effect' request, current lamp state is $light_state");

	# Light needs to be on to be able to program an effect
	$self->set('on');
	
	# Send effect command
	::print_log('hue', "Sending effect command");
	if ($effect ne 'off') {
		$$self{light}->set_state({'effect' => $effect});
	} else {
		$$self{light}->set_state({'effect' => 'none'});
	}
	
	# If the light was off and effect is none, ensure it is back off after we sent the command
	if ($light_state ne 'on' && $effect ne 'on') {
		::print_log('hue', "Restoring light state to off");
		$self->set('off');
	}
	
}

sub bri
{
	my ($self, $value) = @_;
	
	# Sanity check
	if (!(($value =~ /\d+/) && ($value >= 0) && ($value <= 100))) {
		::print_log("Brightness value should be in %, but you passed $value. Brightness not set");
		return;
	}
	
	if ($value == 0){
		::print_log('hue', "Turning lamp off (bri == 0)");
		$self->set('off');
	} else {
		::print_log('hue', "Setting lamp to brightness level $value %");
		# We need to pass a value between 1 and 255 to Device::Hue
		my $scaled = int($value/100*255);
		$self->set('on');
		$$self{light}->bri($scaled);
	}
}

sub ct_k
{
	my ($self, $value) = @_;
	
	# Sanity check
	if (!($value =~ /\d+/)) {
		::print_log("Color temperature in Kelvin should be numeric, but you passed $value. Value not set");
		return;
	}
	
	$self->set('on');
	$$self{light}->ct_k($value);

	::print_log('hue', "Setting color temperature in Kelvin to $value");

}

sub hs
{
	my ($self, $hue, $sat) = @_;
	
	$self->set('on');
	$$self{light}->set_state({'hue' => $hue, 'sat' => $sat});	

	::print_log('hue', "Setting hue and saturation to $hue - $sat");

}

#sub transition_time
#{
#	my ($self, $value) = @_;
#	
#	# Sanity check
#	if (!($value =~ /\d+/)) {
#		::print_log('hue', "Transition time should be numeric");
#		return;
#	}
#	
#	my $scaled = $value*10;
#	$$self{trans_time} = $scaled;
#
#	::print_log('hue', "Setting transition time to $value s for next command");
#
#}

1;
