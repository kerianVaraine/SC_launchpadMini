
//MKtl.find( 'midi' ); //find it
// Use Desc file
////////////////
// m is midicontroller
///////////////
m = MKtl('LPmini', "novation-launchpadMini");
m.reload; // reset after changes to description file
// open Gui
m.gui
//list out all elements, good to check groupings...
m.postElements
// top left pad == k.elAt(\pad, 0, 0);

m = MKtl('LPmini', "novation-launchpadMini");
// Grid pad state array, 0-1
~gridArray = Array.fill(64,{0});

// Toggle Grid Array, 64 pads.
~toggleGridArray = Array.fill(64,{0});

// Top button State array.
~topButtonArray = Array.fill(8,{0});


// Note Lookup for keyboard mode.
~keyboardNoteArray = Array.fill(64, 0);
(
// midi note scale generation for pads...
// take first note of top row(67 here), 35 notes below that is bottom left pad midinote(32 here).
// makes standard isomorphic wiki hayden layout for square pads, so not wiki-hayden layout at all.
// major seconds across, 4ths above.
var note, index;
(7..0).do{|y|
	8.do{|x|
		index = x + (y*8);
		note = 77 + (x*2) - (y*5);
		 ~keyboardNoteArray.put(index, note);
		// [x,y, index, note].postln;
	};
};
)

//Make array for synth voices, 64 for now, as not messing with octave changes just yet;
~synthGridArray = nil ! 64;
// do the same for toggleSynthGridArray to hold toggled synths and not get in the way of keyboard mode.
~toggleSynthGridArray = nil !64



// and a verrrrrry simple synth to start with...
s.boot;
(
SynthDef.new(\tone,{var sig;
	var vib = SinOsc.kr(0.1).bipolar(1);
	var env = EnvGen.kr(
		Env(
			[0, 1, 1, 0],
			[0, 0.8, 2],
			[-2, -4, -4],
			2
		),
		\gate.kr(1),
		doneAction: 2
	);
	sig = MiBraids.ar(\pitch.kr(60), \timb.kr(0.5), \color.kr(0.1), 29, mul: 0.4) ! 2;
	sig = sig * env;
	Out.ar(\out.kr(0), sig);
}).add;


SynthDef.new(\toggleSynth,{
	var sig;
	var pitch=60;
	var bpm = 30/60;
	// var trig = Impulse.kr(bpm);
    var color = LFNoise0.kr(3, 0 ,0.7);
	var vib = SinOsc.kr(0.1).bipolar(1);
	var timb = LFNoise0.kr(3, 0 ,0.7);
	var env = EnvGen.kr(
		Env(
			[0, 1, 1, 0],
			[0.2, 0.8, 2],
			[-2, -4, -4],
			2
		),
		\gate.kr(1),
		doneAction: 2
	);
	sig = MiBraids.ar(\pitch.kr(60), \timb.kr(0.5), \color.kr(LFNoise0.kr(10, 0 ,0.7)), 29, mul: 0.4) ! 2;
	sig = sig * env;
	Out.ar(\out.kr(0), sig *0.5);
}).add;

)


//test synths.
x = Synth(\tone, [pitch: 70, color:0.2, timb:0.9]);
x.set(\gate, 0);

n = Synth(\toggleSynth, [pitch:60]);
n.set(\timb, 0.1)
n.set(\color, LFNoise0.kr(20, 0 ,0.7));
n.set(\gate, 0);
n.free;
// Functions declarations for pads modality actions, and control types
(
//////// General Functions
~printVal = { |el| [el.name, el.value].postln };

~ledOn = {
	arg vel=1;
	{|el| el.value_(vel);}
	/*arg x, y;
	m.elAt( \pad, y,x, \on ).value_(17/127);*/
	// could change to recieve x,y instead of element.... using the m.elAt( \pad, y,x, \on ).do(_.value_(state*(2/127))); like in toggle mode.

};

// straight ledOff function
~ledOff = {
	{|el| el.value_(0);}
};

// For keyboard mode, checks if any key pressed is currently set as a toggled note. if so, it reverts to dull red on noteOff, otherwise turns off.
~ledOffToggleCheck = {
	arg x, y, index, mode;
	switch(mode)
	{ "keyboard" } {
		//check state of toggleGridArray Index, return to dull red if state == 1
		if(~toggleGridArray[index] == 0) {m.elAt(\pad,y,x,\off).value_(0);} {m.elAt( \pad, y,x, \on ).value_(1/127);};
	}
	{ "toggle" }
	{m.elAt(\pad,y,x,\off).value_(0);}
};


///// Reset Actions On Pads for Pad Mode Switching
~padResetOnAction = {
	8.do{|y|
		8.do{|x|
			m.elAt(\pad,y,x,\on).resetAction;
		}
	};
};

~padResetOffAction = {
	8.do{|y|
		8.do{|x|
			m.elAt(\pad,y,x,\off).resetAction;
		}
	}
};

//Top Button Reset actions
~topButtonReset = {
			m.elAt(\top).resetAction;
		};


//////// Toggle Mode Functions Section

~togglePad = {
	arg x, y;
	var index = x + (y * 8), state;
	{ if( ~toggleGridArray[index] != 0) {state = 0} {state = 1};
		~toggleGridArray.put(index, state);
		m.elAt( \pad, y,x, \on ).do(_.value_(state*(2/127)));

	};
};

// Go through all of toggleGridArray send each index to ~togglePlayNote
// This is its own function, as there will be use for this in sequencer mode, checking toggles by column...
~playAllToggledPads = {
	~toggleGridArray.do({
		arg state, index;
				~togglePlayNote.(index, state);
	});
};

// if state of pad == 1, then play note, if note is already playing, so do nothing, if state == 0 and synth existed then syth gate = 0, and turn array index back to nil.
~togglePlayNote = {
	arg index, state;
	var note = ~keyboardNoteArray[index];
	switch(state)
	{1} {	if(~toggleSynthGridArray[index] == nil) {
		~toggleSynthGridArray.put(index,
			Synth(\toggleSynth, [ pitch: note ]).onFree({ ~toggleSynthGridArray[index] = nil });
);
	}}
	{0} { if(~toggleSynthGridArray[index] != nil) {~toggleSynthGridArray.at(index).set(\gate, 0); }}
};


~topButtonAction = {
	arg togglePage;
	~playAllToggledPads.();
};



///////// Extra Useful Toggle Related Functions

// Run through array, Check led state and turn on/off appropriately. To be called after setting toggle in toggle mode
// Called at beginning of keyboard mode to keep toggled notes lit up in a less intense red.
~checkAllLedStates = {
	arg mode;
	~toggleGridArray.do({
		arg state, index;
		m.elAt( \pad, index.div(8),index%8, \on ).do(_.value_(state*(
			switch(mode)
			{"toggle"} {2/127} // if toggle mode, then bright red
		  {"keyboard"} {1/127}))); // if keyboard mode then dull red
	});
};

/////// Keyboard Mode Functions
~padKeyboardNote = {
	arg index, state;
	// [~keyboardNoteArray[index], index%8, index.div(8), state].postln;
	var note = ~keyboardNoteArray[index];
	//Take note, make synth, chuck in array on state == 1, gate off on state == 0;
	switch(state)
	{1} {	~synthGridArray.put(index, Synth(\tone,
		[pitch: note, color:0.2, timb:0.9] ));
	}
	{0} { ~synthGridArray.at(index).set(\gate, 0); }
};

////////////////
// Top Row Button Methods
////////////////



////// Mode Switching, clear existing pad actions and assign new actions to pads depending on mode selected



~padSetAction = {
	arg mode;
	//reset pad actions
	~padResetOnAction.value;
	~padResetOffAction.value;

	switch(mode)
	{ "momentary" } {
			8.do{|y|
				8.do{|x|
					var index = x+(y*8);
					m.elAt(\pad, y, x, \on).addAction(~ledOn.());
					m.elAt(\pad, y, x, \on).addAction({~gridArray.put(index,1)});
					m.elAt(\pad,y, x, \off).addAction(~ledOff.());
					m.elAt(\pad,y, x, \off).addAction({~gridArray.put(index,0)});
				}
			};
		}
	{ "keyboard" } {
				~checkAllLedStates.(mode).value;
			8.do{|y|
				8.do{|x|
								var index = x+(y*8);
					m.elAt(\pad, y, x, \on).addAction(~ledOn.(17/127));
					m.elAt(\pad, y, x, \on).addAction({~gridArray.put(index,1)});
				m.elAt(\pad, y, x, \on).addAction({~padKeyboardNote.(index,1)});
				m.elAt(\pad,y, x, \off).addAction({~ledOffToggleCheck.(x,y,index,mode)});
					m.elAt(\pad,y, x, \off).addAction({~gridArray.put(index,0)});
				m.elAt(\pad, y, x, \off).addAction({~padKeyboardNote.(index,0)});
				// m.elAt(\pad,y, x, \off).addAction(~ledOff.()); // original, works, but turns off toggled notes...
				// m.elAt(\pad,y,x,\off).addAction({~checkAllLedStates.(mode).value}); // not ideal...
				}
			};
		}
	{ "toggle" } {
		~checkAllLedStates.(mode).value;
		8.do{ |y|
				8.do{ |x|
				m.elAt(\pad, y, x, \on).addAction( ~togglePad.(x,y) );
				}
			};
	}
	{
		"Not valid, currently available modes are: 'momentary' , 'keyboard', 'toggle'".postln;
}};

~topSetAction = {
	arg mode;
	switch(mode)
	{"toggle"} {
		8.do{ |x|
			m.elAt(\top, x).addAction( ~topButtonAction);
	}
	{ } {	"Not valid, currently available modes for top buttons are:'toggle'".postln }};
}
)


// main Pad modes.
~padSetAction.("momentary"); // does nothing but light up and turn off when pressed and released. woooooooohooooo
~padSetAction.("keyboard");
~padSetAction.("toggle");

~topSetAction.("toggle");


//could be put on timer, or on execution button... independent of what mode you are currently in.
~playAllToggledPads.value;

~checkAllLedStates.("keyboard").value;



////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////


///// Reset Actions On Pads for Pad Mode Switching

~topButtonReset;

~tArr = Array.fill(8,(0..64));
~tArr[0][5]

(0..64)
//////////////////////////////////////////////
//debugs
~padResetOnAction.value;
~padResetOffAction.value;

~gridArray


~checkLedState.value;
m.elAt(\pad , 0,1, \on).do(_.value_(1));

	// [~keyboardNoteArray[index], index%8, index.div(8), state].postln;

//assign actions to all pads, 8x8
(
8.do{|y|
	8.do{|x|

		m.elAt(\pad, y, x, \on).addAction(~ledOn.((x+(y*8))/127));
		// m.elAt(\pad, y, x, \on).addAction({~gridArray.put(x+(y*8),1)});
		// m.elAt(\pad,y, x, \off).addAction(~ledOff.());
		// m.elAt(\pad,y, x, \off).addAction({~gridArray.put(x+(y*8),0)});
		//[x, y].postln;
		// m.elAt(\pad, y, x).addAction(~printVal);
}};
)

//Clear all LEDS
m.elAt(\pad).do(_.value_(0));


// checking and reseting arrays.
~gridArray
~synthGridArray
~toggleSynthGridArray
~synthGridArray = nil ! 64; //reset synthArray
~toggleSynthGridArray = nil ! 64;
