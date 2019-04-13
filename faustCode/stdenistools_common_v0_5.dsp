//--------------------------------------------------------------------------------------//
//--------------------------------StDenisTools v0.5-------------------------------------//
//
//-----------------------------BY ALAIN BONARDI - 2019----------------------------------//
//--------------------------------------------------------------------------------------//

//Maximum delay size in samples is now 1048576 (and no longer 2097152)
//that is more than 21 seconds at 48 KHz

import("stdfaust.lib");

//--------------------------------------------------------------------------------------//
tablesize = 1 << 16;
sinustable = os.sinwaveform(tablesize);
millisec = ma.SR / 1000.0;

//--------------------------------------------------------------------------------------//
//DEFINITION OF A SMOOTHING LINE
//--------------------------------------------------------------------------------------//
smoothLine = si.smooth(ba.tau2pole(0.05));

//-------------------------------------------------------------------------
// Implementation of Max/MSP line~. Generate signal ramp or envelope 
// 
// USAGE : line(value, time)
// 	value : the desired output value
//	time  : the interpolation time to reach this value (in milliseconds)
//
// NOTE : the interpolation process is restarted every time the desired
// output value changes. The interpolation time is sampled only then.
//
// comes from the maxmsp.lib - no longer standard library
//
//-------------------------------------------------------------------------
line (value, time) = state~(_,_):!,_ 
	with {
		state (t, c) = nt, ba.if (nt <= 0, value, c+(value - c) / nt)
		with {
			nt = ba.if( value != value', samples, t-1);
			samples = time*ma.SR/1000.0;
		};
	};

//--------------------------------------------------------------------------------------//
//DEFINITION OF A PUREDATA LIKE LINEDRIVE OBJECT
//--------------------------------------------------------------------------------------//
pdLineDrive(vol, ti, r, f, b, t) = transitionLineDrive
	with {
			//vol = current volume in Midi (0-127)
			//ti = current time of evolution (in msec)
			//r is the range, usually Midi range (127)
			//f is the factor, usually 2
			//b is the basis, usually 1.07177
			//t is the ramp time usually 30 ms

			pre_val = ba.if (vol < r, vol, r);
			val = ba.if (pre_val < 1, 0, f*pow(b, (pre_val - r)));
			pre_ti = ba.if (ti < 1.46, t, ti);
			transitionLineDrive = line(val, pre_ti);
		};
pdLineDrive4096 = (_, 30, 127, 4096, 1.07177, 30) : pdLineDrive;
basicLineDrive = (_, 30, 127, 1, 1.06, 30) : pdLineDrive;

//--------------------------------------------------------------------------------------//
//--------------------------------------------------------------------------------------//
// PHASOR THAT ACCEPTS BOTH NEGATIVE AND POSITIVE FREQUENCES
//--------------------------------------------------------------------------------------//
pdPhasor(f) = os.phasor(1, f);

//--------------------------------------------------------------------------------------//
// SINUS ENVELOPE
//--------------------------------------------------------------------------------------//
sinusEnvelop(phase) = s1 + d * (s2 - s1)
	with {
			zeroToOnePhase = phase : ma.decimal;
			myIndex = zeroToOnePhase * float(tablesize);
			i1 = int(myIndex);
			d = ma.decimal(myIndex);
			i2 = (i1+1) % int(tablesize);
			s1 = rdtable(tablesize, sinustable, i1);
			s2 = rdtable(tablesize, sinustable, i2);

};

//--------------------------------------------------------------------------------------//
// CONVERSION DB=>LINEAR
//--------------------------------------------------------------------------------------//
dbcontrol = _ <: ((_ > -127.0), ba.db2linear) : *;

//--------------------------------------------------------------------------------------//
//DOUBLE OVERLAPPED DELAY
//--------------------------------------------------------------------------------------//
//
//nsamp is an integer number corresponding to the number of samples of delay
//freq is the frequency of envelopping for the overlapping between the 2 delay lines
//--------------------------------------------------------------------------------------//

maxSampSize = 1048576;
delay21s(nsamp) = de.delay(maxSampSize, nsamp);

overlappedDoubleDelay21s(nsamp, freq) = doubleDelay
	with {
			env1 = freq : pdPhasor : sinusEnvelop : *(0.5) : +(0.5);
			env1c = 1 - env1;
			th1 = (env1 > 0.001) * (env1@1 <= 0.001); //env1 threshold crossing
			th2 = (env1c > 0.001) * (env1c@1 <= 0.001); //env1c threshold crossing
			nsamp1 = nsamp : ba.sAndH(th1);
			nsamp2 = nsamp : ba.sAndH(th2);
			doubleDelay =	_ <: (delay21s(nsamp1), delay21s(nsamp2)) : (*(env1), *(env1c)) : + ;
		};

doubleDelay21s(nsamp) = overlappedDoubleDelay21s(nsamp, 30);


//--------------------------------------------------------------------------------------//
//DEFINITION OF AN ELEMENTARY TRANSPOSITION BLOCK
//--------------------------------------------------------------------------------------//
transpoBlock(moduleOffset, midicents, win) = dopplerDelay
			with {
					freq = midicents : +(6000) : *(0.01) : ba.midikey2hz : -(261.625977) : *(-3.8224) /(float(win));
					//shifted phasor//
					adjustedPhasor = freq : pdPhasor : +(moduleOffset) : ma.decimal;
					//threshold to input new control values//
					th_trigger = (adjustedPhasor > 0.001) * (adjustedPhasor@1 <= 0.001);
					trig_win = win : ba.sAndH(th_trigger);
					delayInSamples = adjustedPhasor : *(trig_win) : *(millisec);
					variableDelay = de.fdelay(262144, delayInSamples);
					cosinusEnvelop = adjustedPhasor : *(0.5) : sinusEnvelop;
					dopplerDelay = (variableDelay, cosinusEnvelop) : * ;
				};


overlapped4Harmo(tra, win) = _ <: par(i, 4, transpoBlock(i/4, tra, win)) :> *(0.5) ;

//--------------------------------------------------------------------------------------//
//AMBISONICS SPATIALIZER
//--------------------------------------------------------------------------------------//
//ajout d'une phase//
pdPhasorWithPhase(f, p, tog) = (1-vn) * x + vn * p
with {
		vn = (f == 0);
		x = (pdPhasor(f)*tog, p, 1) : (+, _) : fmod;
};
//phasedAngle(f, p, tog) = pdPhasorWithPhase(f, p, tog) * 2 * ma.PI;

myEncoder(sig, angle) = ho.encoder(1, sig, angle);
//a(ind) = hslider("h:decoder/v:angles/a%ind [unit:deg]", ind * 45, -360, 360, 1) * ma.PI / 180;
a(ind) = ind * ma.PI * 0.25;
phasedEncoder(f, p, tog) = (_, (pdPhasorWithPhase(f, p, tog) <: (_, _))) : (_, *(2 * ma.PI), _) : (myEncoder, _);//outputs the encoded signal at order 1 + the angle between 0 and 1

//--------------------------------------------------------------------------------------//
//AMBISONIC DECODING WITH IRREGULAR ORDER
//-------------------------------------------------------------------
mydecoder(n, p)	= par(i, 2*n+1, _) <: par(i, p, speaker(n, a(i)))
with 
{
   speaker(n,alpha)	= /(2), par(i, 2*n, _), ho.encoder(n,2/(2*n+1),alpha) : si.dot(2*n+1);
};


//--------------------------------------------------------------------------------------//
//EQUIVALENT OF REV4~ IN FAUST WITH QUADRIPHONIC OUTPUT
//--------------------------------------------------------------------------------------//
//2 controls: revDur which is the duration of the reverb (127 is infinite)
//revAmp is the amplitude of the output sound of the reverb

tap(del) = de.delay(65536, int(del * millisec));
initBlock(del) = _ <: (_, tap(del)) <: (+, -);
plusMinusBlock(del) = (_, tap(del)) <: (+, -);
cascadBlock = initBlock(75.254601) : plusMinusBlock(43.533688) : plusMinusBlock(25.796) : plusMinusBlock(19.391993) : plusMinusBlock(16.363997) : (_, tap(13.645));
inputSort(n) = si.bus(2*n) <: par(i, n, (ba.selector(i, 2*n), ba.selector(i+n, 2*n)));
doubler4to8 = ((_<:(_, _)), (_<:(_, _)), (_<:(_, _)), (_<:(_, _)));

p(a, b, c, d, e, f, g, h) = (e, a, g, c, f, b, h, d);
reinjBlock1 = (*(revDur), *(revDur), *(revDur), *(revDur), _, _) : (_, _, inputSort(2)) : (_, _, +, +);
reinjBlock2 = (((_, _) <: (_, _, (-:*(-1)), +)), ((_, _) <:((-:*(-1)), +, _, _))) : (_, _, doubler4to8, _, _) : (_, _, p, _, _) : (*(revGain), *(revGain), -, -, +, +, *(revGain), *(revGain));
reinjBlock3 = (tap(58.643494), tap(69.432503), tap(74.523392), tap(86.12439));

rev4quadri = cascadBlock : (reinjBlock1 : reinjBlock2) ~ (!, !, reinjBlock3, !, !) : (_, _, !, !, !, !, _, _);


//--------------------------------------------------------------------------------------//
//CONTROL PARAMETERS FOR PROCESSES
//--------------------------------------------------------------------------------------//
//Size of the harmonizer window for Doppler effect//
//hWin = hslider("h:Global_Parameters/hWin", 64, 1, 127, 0.01) : pdLineDrive4096;
hWin = 64 : pdLineDrive4096;
//Delays 1 and 2 => Blocks 1 and 3//
d1 = int(hslider("d1", 100, 0, 21000, 1)*millisec);
d3 = int(hslider("d3", 200, 0, 21000, 1)*millisec);
fd1 = hslider("fd1", 0.8, 0, 0.99, 0.01);
fd3 = hslider("fd3", 0.8, 0, 0.99, 0.01);
v1 = hslider("v1 [unit:dB]", -127, -127, 18, 0.01):smoothLine:dbcontrol;
v3 = hslider("v3 [unit:dB]", -127, -127, 18, 0.01):smoothLine:dbcontrol;
//Pitch shifter => Block 4
tra4 = hslider("tra4", 0, -2400, 2400, 0.01);
fd4 = hslider("fd4", 0.4, 0, 0.99, 0.01);
v4 = hslider("v4 [unit:dB]", -127, -127, 18, 0.01):smoothLine:dbcontrol;
//spatialization of processes
//original angles
//ang1 = hslider("ang1", 0.25, 0, 1, 0.01);
//ang3 = hslider("ang3", 0.75, 0, 1, 0.01);
//ang4 = hslider("ang4", 0.5, 0, 1, 0.01);
ang1 = -0.25;
ang3 = 0.25;
ang4 = 0;
//no angle for rev4~ since the output is direct
//rotation speed
sp1 = hslider("sp1", 0.1, -5, 5, 0.01);
sp3 = hslider("sp3", 0.05, -5, 5, 0.01);
sp4 = hslider("sp4", 0.15, -5, 5, 0.01);
//toggles to trigger rotations
//reverse (-1) / off (0) / on (1)
tog1 = hslider("tog1", 0, -1, 1, 1);
tog3 = hslider("tog3", 0, -1, 1, 1);
tog4 = hslider("tog4", 0, -1, 1, 1);
//Block2 - infinite reverb//
//parameters to control the infinite reverb//
revDur = hslider("revDur", 120, 0, 127, 1) : /(254.) : smoothLine;
revGain = hslider("revGain", 127, 0, 127, 1) : basicLineDrive;
v2 = hslider("v2 [unit:dB]", -127, -127, 18, 0.01):smoothLine:dbcontrol: *(0.1);
gainv2 = par(i, 4, *(v2));
//
gain = hslider("gain [unit:dB]", 0, -127, 18, 0.01) : smoothLine : dbcontrol;
gain4 = par(i, 4, *(gain));
gain2 = (*(gain), *(gain));
//
//first block with sound inputs and modules without spatialization
del1 = (+ : doubleDelay21s(d1)) ~ (*(fd1)) : *(v1);
del3 = (+ : doubleDelay21s(d3)) ~ (*(fd3)) : *(v3);
pitchshifter4 = (+ : overlapped4Harmo(tra4, hWin)) ~ (*(fd4)) : *(v4);
block2 = rev4quadri : gainv2;
firstBlock = (block2, del1, del3, pitchshifter4) <: si.bus(14); //first block
//
//second block with spatialization
//
spat1 = phasedEncoder(sp1, ang1, tog1);
spat3 = phasedEncoder(sp3, ang3, tog3);
spat4 = phasedEncoder(sp4, ang4, tog4);
threeToOne = ((_, _, _) :> _);
ptodecoder(a, b, c, d, e, f, g, h, i, j, k, l) = (a, e, i, b, f, j, c, g, k, d, h, l) : (threeToOne, threeToOne, threeToOne, _, _, _);
//the second block and process are adapted to each configuration: quadri and stereo//

