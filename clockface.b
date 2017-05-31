# Model 1
implement Clockface;

include "sys.m";
include "draw.m";

Clockface : module {
	init : fn (ctxt : ref Draw->Context, argv : list of string);
};

sys : Sys;

hmpath : con "motor/0";		# hour-hand motor
mmpath : con "motor/2";		# minute-hand motor
allmpath : con "motor/012";	# all motors (for stopall msg)

hbpath : con "sensor/0";		# hour-hand sensor
mbpath : con "sensor/2";		# minute-hand sensor
lspath: con "sensor/1";		# light sensor;

ONTHRESH : con 780;		# light sensor thresholds
OFFTHRESH : con 740;
NCLICKS : con 120;
MINCLICKS : con 2;			# min number of clicks required to stop a motor

Hand : adt {
	motor : ref Sys->FD;
	sensor : ref Sys->FD;
	fwd : array of byte;
	rev : array of byte;
	stop : array of byte;
	pos : int;
};


lightsensor : ref Sys->FD;
allmotors : ref Sys->FD;
hourhand : ref Hand;
minutehand : ref Hand;

init(nil : ref Draw->Context, argv : list of string)
{
	sys = load Sys Sys->PATH;

	argv = tl argv;
	if (len argv != 1) {
		sys->print("usage: lego_dir\n");
		sys->raise("fail:usage");
	}

	# set up our control file
	if (sys->bind("#s", ".", Sys->MBEFORE) == -1) {
		sys->print("failed to bind srv device: %r\n");
		return;
	}
	f2c := sys->file2chan(".", "clockface");
	if (f2c == nil) {
		sys->print("cannot create legolink channel: %r\n");
		return;
	}

	legodir := hd argv;
	if (legodir[len legodir -1] != '/')
		legodir[len legodir] = '/';

	# get the motor files
	sys->print("opening motor files\n");
	hm := sys->open(legodir + hmpath, Sys->OWRITE);
	mm := sys->open(legodir +mmpath, Sys->OWRITE);
	allmotors = sys->open(legodir + allmpath, Sys->OWRITE);
	if (hm == nil || mm == nil || allmotors == nil) {
		sys->print("cannot open motor files\n");
		sys->raise("fail:error");
	}

	# get the sensor files
	sys->print("opening sensor files\n");
	hb := sys->open(legodir + hbpath, Sys->ORDWR);
	mb := sys->open(legodir + mbpath, Sys->ORDWR);
	lightsensor = sys->open(legodir + lspath, Sys->ORDWR);

	if (hb == nil || mb == nil) {
		sys->print("cannot open sensor files\n");
		sys->raise("fail:error");
	}

	hourhand = ref Hand(hm, hb, array of byte "r7", array of byte "f7", array of byte "s7", 0);
	minutehand = ref Hand(mm, mb, array of byte "f7", array of byte "r7", array of byte "s7", 0);

	sys->print("setting sensor types\n");
	setsensortypes(hourhand, minutehand, lightsensor);

	# get the hands to 12 o'clock
	reset();
	sys->print("H %d, M %d\n", hourhand.pos,minutehand.pos);
	spawn srvlink(f2c);
}

srvlink(f2c : ref Sys->FileIO)
{
	busy := 0;
	done := chan of int;
	for (;;) alt {
	(offset, count, fid, rc) := <- f2c.read =>
		if (rc == nil)
			continue;
		rc <- = (nil, "busy");
	(offset, data, fid, wc) := <- f2c.write =>
		if (wc == nil)
			continue;
		if (busy)
			wc <- = (0, "busy");
		else {
			spawn sethands(done, string data);
			wc <- = (len data, nil);
		}
	<- done =>
		sys->print("H %d, M %d\n", hourhand.pos,minutehand.pos);
		busy = 0;
	}
}

str2clicks(s : string) : (int, int)
{
	h, m : int = 0;
	(n, toks) := sys->tokenize(s, ":");
	if (n > 1) {
		h = int hd toks;
		toks = tl toks;
		n--;
	}
	if (n > 0) {
		m = int hd toks;
	}
	h = ((h * NCLICKS) / 12) + ((m * NCLICKS) / (12 * 60));
	m = (m * NCLICKS)/60;
	return (h, m);
}

sethands(done : chan of int, time : string)
{
	(hclk, mclk) := str2clicks(time);
	for (i := 0; i < 6; i++) {
		hdelta := clickdistance(hourhand.pos, hclk, NCLICKS);
		mdelta := clickdistance(minutehand.pos, mclk, NCLICKS);
		if (hdelta == 0 && mdelta == 0)
			break;
		hrep := chan of int;
		mrep := chan of int;
		nspawned := 0;
		if (hdelta != 0) {
			nspawned++;
			spawn sethand(hrep, hourhand, hdelta);
			<- hrep;
		}
		if (mdelta != 0) {
			nspawned++;
			spawn sethand(mrep, minutehand, mdelta);
			<- mrep;
		}
#		while (nspawned > 0) alt {
#		val := <- hrep =>
#			nspawned--;
#		val := <- mrep =>
#			nspawned--;
#		}
	}
	releaseall();
	done <- = 1;
}

clickdistance(start, stop, mod : int) : int
{
	if (start > stop)
		stop += mod;
	d := (stop - start) % mod;
	if (d > mod/2)
		d -= mod;
	return d;
}

setsensortypes(h1, h2 : ref Hand, ls : ref Sys->FD)
{
	button := array of byte "b0";
	light := array of byte "l0";

	sys->write(h1.sensor, button, len button);
	sys->write(h2.sensor, button, len button);
	sys->write(ls, light, len light);
}

HOUR_ADJUST : con 1;
MINUTE_ADJUST : con 2;
reset()
{
	# run the motors until hands are well away from 12 o'clock (below threshold)

	val := readsensor(lightsensor);
	if (val > OFFTHRESH) {
		triggered := chan of int;
		sys->print("wait for hands clear of light sensor\n");
		spawn lightwait(triggered, lightsensor, 0);
		forward(minutehand);
		reverse(hourhand);
		val = <- triggered;
		stopall();
		sys->print("sensor %d\n", val);
	}

	resethand(hourhand);
	hourhand.pos += HOUR_ADJUST;
	resethand(minutehand);
	minutehand.pos += MINUTE_ADJUST;
	done := chan of int;
	spawn sethands(done, "12:00");
	<- done;
}

sethand(reply : chan of int, hand : ref Hand, delta : int)
{
	triggered := chan of int;
	dir := 1;
	if (delta < 0) {
		dir = -1;
		delta = -delta;
	}
	if (delta > MINCLICKS) {
		spawn handwait(triggered, hand, delta - MINCLICKS);
		if (dir > 0)
			forward(hand);
		else
			reverse(hand);
		<- triggered;
		stop(hand);
	hand.pos += dir * readsensor(hand.sensor);
	} else {
		startval := readsensor(hand.sensor);
		if (dir > 0)
			forward(hand);
		else
			reverse(hand);
		stop(hand);
		hand.pos += dir * (readsensor(hand.sensor) - startval);
	}
	if (hand.pos < 0)
		hand.pos += NCLICKS;
	hand.pos %= NCLICKS;
	reply <- = 1;
}

resethand(hand : ref Hand)
{
	triggered := chan of int;
	val : int;

	# run the hand until the light sensor is above threshold
	sys->print("running hand until light sensor activated\n");
	spawn lightwait(triggered, lightsensor, 1);
	forward(hand);
	val = <- triggered;
	stop(hand);
	sys->print("sensor %d\n", val);

	startclick := readsensor(hand.sensor);

	# advance until light sensor drops below threshold
	sys->print("running hand until light sensor clear\n");
	spawn lightwait(triggered, lightsensor, 0);
	forward(hand);
	val = <- triggered;
	stop(hand);
	sys->print("sensor %d\n", val);
	
	stopclick := readsensor(hand.sensor);
	nclicks := stopclick - startclick;
	sys->print("startpos %d, endpos %d (nclicks %d)\n", startclick, stopclick, nclicks);

	hand.pos = nclicks/2;
}

stop(hand : ref Hand)
{
	sys->seek(hand.motor, 0, Sys->SEEKSTART);
	sys->write(hand.motor, hand.stop, len hand.stop);
}

stopall()
{
	msg := array of byte "s0s0s0";
	sys->seek(allmotors, 0, Sys->SEEKSTART);
	sys->write(allmotors, msg, len msg);
}

releaseall()
{
	msg := array of byte "F0F0F0";
	sys->seek(allmotors, 0, Sys->SEEKSTART);
	sys->write(allmotors, msg, len msg);
}

forward(hand : ref Hand)
{
	sys->seek(hand.motor, 0, Sys->SEEKSTART);
	sys->write(hand.motor, hand.fwd, len hand.fwd);
}

reverse(hand : ref Hand)
{
	sys->seek(hand.motor, 0, Sys->SEEKSTART);
	sys->write(hand.motor, hand.rev, len hand.rev);
}

readsensor(fd : ref Sys->FD) : int
{
	buf := array [4] of byte;
	sys->seek(fd, 0, Sys->SEEKSTART);
	n := sys->read(fd, buf, len buf);
	if (n <= 0)
		return -1;
	return int string buf[0:n];
}

handwait(reply : chan of int, hand : ref Hand, clicks : int)
{
	blk := array of byte ("b" + string clicks);
	sys->seek(hand.sensor, 0, Sys->SEEKSTART);
	sys->print("handwait(%s)\n", string blk);
	if (sys->write(hand.sensor, blk, len blk) != len blk)
	sys->print("handwait write error: %r\n");
	reply <- = readsensor(hand.sensor);
}

lightwait(reply : chan of int, fd : ref Sys->FD, on : int)
{
	thresh := "";
	if (on)
		thresh = "l>" + string ONTHRESH;
	else
		thresh = "l<" + string OFFTHRESH;
	blk := array of byte (thresh);
	sys->print("lightwait(%s)\n", string blk);
	sys->seek(fd, 0, Sys->SEEKSTART);
	sys->write(fd, blk, len blk);
	reply <- = readsensor(fd);
}