/////////////////////////////////////////////
// Install Dependencies:
// Modaility toolkit for mapping controller
// Quarks.install("Modality-toolkit");
////
// Mutable Instruments UGens for basic sound design, follow install instructions:
// https://github.com/v7b1/mi-UGens

/////////////////////////////////////////////

// First block initialises controller, global arrays & variables
(
m = MKtl('LPmini', "novation-launchpadMini");

//Global 8x8 pad mode, "keyboard", "toggle", "sequencer" only availasble.
~padMode ="keyboard"; //current mode
~nextPadMode = "keyboard"; // next mode, inits to same...

// Grid pad state array, 0-1
~gridArray = Array.fill(64,{0});

// Toggle Grid Array, 8 pages of 64 pads, plus 1 page of all 0s for page off.
~toggleGridArray = Array.fill2D(9, 64, 0);

//Array to hold synths whose gate has been turned off, making room for new synths in same spot of toggleGridArray...
~releasingSynths = [];

// Top button State array.
~topButtonArray = [1,0,0,0,0,0,0,0];
~currentTogglePage = 0;

// Note Lookup for keyboard mode.
// TODO: make this array generation nicer, or more modular for different layouts
~keyboardNoteArray = Array.fill(64, 0);
~defineKeyboardNoteArray = {
	// midi note scale generation for pads...
	// take first note of top row(77 here), 35 notes below that is bottom left pad midinote(32 here).
	// makes standard isomorphic wiki hayden layout for square pads, so not wiki-hayden layout at all.
	// major seconds across, 4ths above.
	arg bottomLeftPadNote;
	var note, index,topLeftPadNote = bottomLeftPadNote + 35;
	(7..0).do{|y|
		8.do{|x|
			index = x + (y*8);
			note = topLeftPadNote + (x*2) - (y*5);
			~keyboardNoteArray.put(index, note);
			// [x,y, index, note].postln;
		};
	};
};
~defineKeyboardNoteArray.(40).value;

//Make array for synth voices, 64 for now, as not messing with octave changes just yet;
~synthGridArray = nil ! 64;

// do the same for toggleSynthGridArray to hold toggled synths and not get in the way of keyboard mode.
~toggleSynthGridArray = nil !64;

// Keyboard mode recording Sequencer array
~sequenceSynthGridArray = nil ! 64;


//Toggle Sequencer vars
~playPosition = 0;
~playState = 0;

// 64 pad array for sequenced togglePages... song mode?
// takes togglePageNumber as arg, 8 is blank
// light them up dullest yellow for playback, 16/127
//array filled with blank toggle page number.
~sequencerArray = Array.fill(64,8);


)


// Second block initialise a verrrrrry simple synth to start with...
// swapped synths - 14-04-22
(
s.waitForBoot;

// bowed lead. doesn't go well with wobbley tubes.
SynthDef.new(\toggleSynth,{var sig;
	var vib = SinOsc.kr(0.1).bipolar(1);
		var color = SinOsc.kr(LFNoise1.kr(5,2,0)).unipolar(1);
	var env = EnvGen.kr(
		Env(
			[0, 1, 1, 0],
			[0, 0.8, 1],
			[-2, -4, -4],
			2
		),
		\gate.kr(1),
		doneAction: 2
	);
	var timbreEnv = EnvGen.kr(Env([0,1,0.3],[0,0.3,4],'exp'));
	sig = MiBraids.ar(\pitch.kr(60), timbreEnv, color, 29, mul: 0.1) ! 2;
	sig = sig * env;
	Out.ar(\out.kr(0), sig);
}).add;


/// Wobbley overblown tubes
SynthDef.new(\tone,{
	var sig;
	var pitch=60;
	var bpm = 30/60;
	var panVal = SinOsc.kr(LFNoise1.kr(3,1),Prand([0,0.25,0.5,0.75],inf).asStream).linlin(-1.0,1.0,-0.7,0.7);
	var color = SinOsc.kr(LFNoise1.kr(5,0.5,0)).unipolar(1);
	var vib = SinOsc.kr(3).bipolar(0.1);
	var timb = SinOsc.kr(0.25,0.5).linlin(-1,1,0.8,1);
	var env = EnvGen.kr(
		Env(
			[0, 1, 1, 0],
			[0.2, 0.8, 1],
			[-2, -4, -4],
			2
		),
		\gate.kr(1),
		doneAction: 2
	);
	sig = MiBraids.ar(\pitch.kr(60) + vib, timb, color, model:31, mul: 0.1);
	sig = sig * env;
		Out.ar(\out.kr(0), Pan2.ar(sig, panVal));
}).add;
)

/////////////////////////////////////////////
//test simple synths.
x = Synth(\tone, [pitch: 70, color:0.2, timb:0.9]);
x.set(\gate, 0);

n = Synth(\toggleSynth, [pitch:60]);
n.set(\timb, 0.9)
n.set(\color, 0.9);
n.set(\gate, 0);
n.free;



//For pads, model 31, timbre 1, modulate colour from 0-1 slowly for harmnoic series with overblown kind of sound




/////////////////////////////////////////////

// Main block does all the things.
// Functions declarations for pads modality actions, and control types.
// Inits default keyboard mode for pads, with 'A' button switching modes, and top row of numbered buttons holding pages of toggled notes.
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
		if(~toggleGridArray[~currentTogglePage][index] == 0) {m.elAt(\pad,y,x,\off).value_(0);} {m.elAt( \pad, y,x, \on ).value_(1/127);};
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
	8.do{|x|
		m.elAt(\top, x).resetAction;
	}
};

/////////////////////////////////
/////// Keyboard Mode Functions

~padKeyboardNote= {
	arg index, state;
//	[~keyboardNoteArray[index], index%8, index.div(8), state].postln;
	var note = ~keyboardNoteArray[index];
	//Take note, make synth, chuck in array on state == 1, gate off on state == 0;
	switch(state)
	{1} {	~synthGridArray.put(index, Synth(\tone,
		[pitch: note] ));}
	{0} { ~synthGridArray.at(index).set(\gate, 0); };

	if(~keySeqRecording == true){
		~keyRecordNoteEvents.(index,state);
	};
};

//////// Toggle Mode Functions Section

~togglePad = {
	arg x, y;
	var index = x + (y * 8), state;
	{if(~currentTogglePage != 8)
		{ if( ~toggleGridArray[~currentTogglePage][index] != 0) {state = 0} {state = 1};
			~toggleGridArray[~currentTogglePage].put(index, state);
			m.elAt( \pad, y,x, \on ).do(_.value_(state*(2/127)));
		};
	};
};

// Go through all of toggleGridArray send each index to ~togglePlayNote
// This is its own function, as there will be use for this in sequencer mode, checking toggles by column...
~playAllToggledPads = {
	~toggleGridArray[~currentTogglePage].do({
		arg state, index;
		~togglePlayNote.(index, state);
	});
};

// if state of pad == 1, then play note, if note is already playing, so do nothing, if state == 0 and synth existed then syth gate = 0, send synth to synthReleaseGraveyard and turn array index back to nil.
~togglePlayNote = {
	arg index, state;
	var note = ~keyboardNoteArray[index];
	switch(state)
	{1} {	if(~toggleSynthGridArray[index] == nil) {
		~toggleSynthGridArray.put(index,
			// Synth(\toggleSynth, [ pitch: note ]).onFree({ ~toggleSynthGridArray[index] = nil });
			Synth(\toggleSynth, [ pitch: note ]);

	);}}

	{0} { if(~toggleSynthGridArray[index] != nil) {
		~toggleSynthGridArray.at(index).set(\gate, 0); // start release of envelope
		//make bundle sends message at same time in explicit order given
		s.makeBundle(nil, {
			~releasingSynths.add(~toggleSynthGridArray[index]); //put synth into synth graveyard array
			~toggleSynthGridArray[index] = nil; // set index to nil in toggleSynthArray.... obviously?
		});
	}
	}

};


/// Top button related...
~setTopButtonPageLed = {
	8.do{|x|
		if( x == ~currentTogglePage) { m.elAt(\top,x).value_(1); } { m.elAt(\top,x).value_(0); }
	};
};


~topButtonAction = {
	arg togglePage, val;
	// top buttons are midiCC, so anything other than 0 should trigger play.
	if(val !=0){
		//Clear all top button leds
		//turn on selected one


		switch(~playState)
				//if same page number is pressed again, load blank toggle page array @ index[8], other wise, change to new page.
		{0} {if(~currentTogglePage == togglePage)
		{ ~currentTogglePage = 8;	} //toggle page of nothingness.
		{ ~currentTogglePage = togglePage; };
		}
		    //if playing sequences, hold onto page.
		{1} { ~currentTogglePage = togglePage; };

		//set top button led state...
		~setTopButtonPageLed.value;
		//reset toggleGridLeds
		~checkAllLedStates.("toggle").value;
		// Set play position for sequence tests along top row... out for sequencer mode
		// ~playPosition = ~currentTogglePage;
		//then playAllTogglePads.
		~playAllToggledPads.value;
		//

	};
};

///////// Extra Useful Toggle Related Functions

// Run through array, Check led state and turn on/off appropriately. To be called after setting toggle in toggle mode
// Called at beginning of keyboard mode to keep toggled notes lit up in a less intense red.
~checkAllLedStates = {
	arg mode;
	~toggleGridArray[~currentTogglePage].do({
		arg state, index;

		m.elAt( \pad, index.div(8),index%8, \on ).do(_.value_(state*(
			switch(mode)
			{"toggle"} {2/127} // if toggle mode, then bright red
			{"keyboard"} {1/127}
		{"sequencer"} {0/127};))); // if keyboard or sequencer mode then dull red
		// Check if keyboard note is being played, if so turn led back to keyboard colour.
		if ( ~gridArray[index] == 1 ) {	m.elAt( \pad, index.div(8), index%8, \on).do(_.value_(17/127))};
	});
};

////////////////////////////////////////////
//////// Sequencer Mode Functions Section //

~sequencePadUpdateLed = {
	var state, pageHighlight;
		//do.array, set leds...
	if( ~padMode == "sequencer" ) {
		~sequencerArray.do(
			{arg item, index;
		switch(item)
			{8} {state = 0; pageHighlight = 0;}
			{~currentTogglePage} {state = 1; pageHighlight = 6;}
		//default
			{state = 1; pageHighlight = 0;};

				m.elAt( \pad, index.div(8),index%8, \on ).do(_.value_(state*((17+ pageHighlight)/127) ));
		});
	};
};

~sequencerPad = {
	arg x, y;
	var index = x+(y*8);
	{ ~sequencerArray.put(index, if(~sequencerArray[index] == ~currentTogglePage) {8;}{~currentTogglePage;}; );
		~sequencePadUpdateLed.value;
	};
};



////////////////////////////
// Toggle Pages Sequencer //
// Task for running through togglePages via ~topButtonAction.... not ideal, but works?
~toggleSeq = Task({
	var interval = 0.22; // here is tempo...
	loop {
		~playPosition = (~playPosition + 1).wrap(0,63);
		~topButtonAction.(~sequencerArray[~playPosition]);
		m.elAt( \pad, ~playPosition.div(8),~playPosition%8, \on ).do(_.value_(18/127)); //plackback Marker show.
		interval.wait;
	}
});

// H Button action
~playToggleSeq = {
	if(~playState==0) { ~toggleSeq.play; ~playState = 1;} { ~toggleSeq.stop; ~playState = 0;};
};




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
		~setTopButtonPageLed.value;
	}
	{ "sequencer" } {
				~checkAllLedStates.(mode).value;
					8.do{ |y|
			8.do{ |x|
				m.elAt(\pad, y, x, \on).addAction( ~sequencerPad.(x,y) );
			}
		};
	}
	{
		"Not valid, currently available modes are: 'momentary' , 'keyboard', 'toggle'".postln;
}};

///////////////////////////
// Top Row Button Methods /
///////////////////////////

~topSetAction = {
	arg mode;
	~topButtonReset.value;
	switch(mode)
	{"toggle"} {
		8.do{ |x|
			m.elAt(\top, x).addAction( {~topButtonAction.(x, m.elAt(\top, x).value.round(0.0001))});
			m.elAt(\top,x).addAction( {~sequencePadUpdateLed.value; } );
		}
		{ } {	"Not valid, currently available modes for top buttons are:'toggle'".postln }};
};

////////////////////////////
// Side Row Button Methods /
////////////////////////////

~sideSetAction = {
	m.elAt(\side, 0,\on).resetAction;

	m.elAt(\side, 0,\on).addAction( {
		~padMode = ~nextPadMode.value;
		switch(~nextPadMode)
		{"keyboard"} {
			~padSetAction.("keyboard"); ~nextPadMode = "toggle";
			"keyboardMode!".postln;
			m.elAt(\side, 0,\on).value_(17/127);
		}
		{"toggle"} {
			~padSetAction.("toggle"); ~nextPadMode = "sequencer";
			"toggleMode!".postln;
			m.elAt(\side, 0,\on).value_(3/127);
		}
		{"sequencer"} {
			~padSetAction.("sequencer");  ~nextPadMode = "keyboard";
			"sequencerMode!".postln;
		m.elAt(\side, 0,\on).value_(16/127);
			~sequencePadUpdateLed.value;
		};

		//Play toggle Pages with H
		m.elAt(\side, 7,\on).resetAction;
		//Play Action on H Button:
		m.elAt(\side, 7,\on).addAction( {~playToggleSeq.value});

		//G start recording, only works first time, just wanted to play...
		m.elAt(\side,6, \on).resetAction;
		m.elAt(\side,6, \on).addAction( { ~recordKeyboardButton.value });

		~padMode.postln;
})};


//////////////////////////////////////
//Init Controller to keyboard mode  //
//////////////////////////////////////

~padSetAction.("keyboard");
~topSetAction.("toggle");
~padMode = "keyboard";
~sideSetAction.value;

)

////////////////////////////
// Now it should all work! /
////////////////////////////



///Recording sweet jams.
~playPosition=0
s.makeWindow;
Platform.recordingsDir


///////////
// Keyboard Transposition, define bottom left pad value
~defineKeyboardNoteArray.(46).value;



/////////////////////////////////////////
// Keyboard Sequencer recording mode??
// Records keyboard notes can play them back in their own array of synths.
/////////
// Testing array of keyOn/Off events, see if I can record an array of them and paly them back...
// Has to be a function call...

(

		//init vars
		~keySeqRecording = false; // true for recording mode...
		~keyTestArray = nil!100; // read at control rate?
		~keyRecordArray = List.new;
		~keyTestArrayPos = 0; //playhead

		// sequencer specific synth creation using array defined in header code.
		~keyPlaySeq = Task({
			var interval = 0.1; // here is tempo...
			loop {
				~keyTestArrayPos.postln;
				~keyTestArray[~keyTestArrayPos].postln;
				if (~keyTestArray[~keyTestArrayPos] != nil) {
					// works for monophonic
					// ~padKeyboardNote.(~keyTestArray[~keyTestArrayPos][0], ~keyTestArray[~keyTestArrayPos][1]);
					//testing for nested arrays of note events
					~keyTestArray[~keyTestArrayPos].do({ arg item ;
						~keySeqPlayNotes.(item[0], item[1]);
					});
				};
				~keyTestArrayPos = (~keyTestArrayPos + 1).wrap(0,~keyTestArray.size);
				interval.wait;
			}
		});


		// Recording into list, creates a nil input to keep time.
		~keyRecordSeq = Task({
			var interval = 0.1; // here is tempo...
			loop {
				~keyTestArrayPos.postln;
				~keyRecordArray.add(nil);
				~keyTestArrayPos = (~keyTestArrayPos + 1);
				interval.wait;
		}};
		);

		// called from PadKeyboardNote if record mode true
		~keyRecordNoteEvents = {
			arg index,state;
			if(~keyRecordArray[~keyTestArrayPos-1].size == 0){
				~keyRecordArray.put(~keyTestArrayPos-1, [[index, state]] );
			} {
				~keyRecordArray[~keyTestArrayPos-1].add( [index, state] );
			}
		};


		// playback opf recorded sequence, makes new synths per note.
		~keySeqPlayNotes = {
			arg index, state;
			//	[~keyboardNoteArray[index], index%8, index.div(8), state].postln;
			var note = ~keyboardNoteArray[index];
			//Take note, make synth, chuck in array on state == 1, gate off on state == 0;
			switch(state)
			{1} {	~sequenceSynthGridArray.put(index, Synth(\tone,
				[pitch: note] ));}
			{0} { ~sequenceSynthGridArray.at(index).set(\gate, 0); };

			if(~keySeqRecording == true){
				~keyRecordNoteEvents.(index,state);
			};
		};




		// Controls for sequencer
		/////
		//Recording
// ADD start on input would be nice.
		~recordKeyboardButton = {
			if( ~keySeqRecording == false) {
		"startingRecording".postln;
				// clear and reset arrayList
				~keyRecordArray.clear; ~keyTestArrayPos = 0;
				// Set recording on and start recordin keypresses
				~keySeqRecording = true; ~keyRecordSeq.play;
			}{
				"stoppingRecording".postln;
				// stop recording and set recording to false
				~keyRecordSeq.stop; ~keySeqRecording = false;
				// push list to key recorded arrary
				~keyTestArray = ~keyRecordArray.asArray;
		//then play automagically
		    ~keyTestArrayPos = 0;~keyPlaySeq.play;

			};
		};

	)		/////////////


	// Playback
// play and stop recorded array
~keyTestArrayPos = 0;~keyPlaySeq.play;
~keyPlaySeq.stop;~keyTestArrayPos = 0;







//////////////////////////////
// random debugs section.... /
//////////////////////////////



m.reload;

//could be put on timer, or on execution button... independent of what mode you are currently in.
~playAllToggledPads.value;

~checkAllLedStates.("toggle").value;



////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////

~releasingSynths
~toggleSynthGridArray


s.makeBundle

///// Reset Actions On Pads for Pad Mode Switching

~topButtonReset.value;

~padResetOnAction.value;
~padResetOffAction.value;

~gridArray


~checkLedState.value;


// [~keyboardNoteArray[index], index%8, index.div(8), state].postln;

//assign actions to all pads, 8x8
(
8.do{|y|
	8.do{|x|

		m.elAt(\pad, y, x, \on).addAction(~ledOn.((x+(y*16))/127));
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

~toggleGridArray



/////////////////////////////
// Was at top of file, used for initial controller mapping
// s.reboot;
// //MKtl.find( 'midi' ); //find it
// // Use Desc file
// ////////////////
// // m is midicontroller
// ///////////////
// m = MKtl('LPmini', "novation-launchpadMini");
// m.reload; // reset after changes to description file
// // open Gui
// m.gui
// //list out all elements, good to check groupings...
 m.postElements
// // top left pad == k.elAt(\pad, 0, 0);

/////////////////////////////////////////////
// ndef messing for sounddesign... not quite for this, need to learn more.
/*(
Ndef(\keyboard, {| pitch=60, timbre= 0.5, color = 0.5, model = 29 |
	var sig;
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
	sig = MiBraids.ar(pitch, timbre, color, model, mul: 0.4) ! 2;
	sig = sig * env;
});
)
s.reboot
Ndef(\keyboard).addSpec(\pitch, [30,70,\lin, 1.0]);
Ndef(\keyboard).addSpec(\timbre, [0.0,1.0,\lin, 0.0]);
Ndef(\keyboard).addSpec(\color, [0.0,1.0,\lin, 0.0]);
Ndef(\keyboard).addSpec(\model, [0,47,\lin, 1.0]);

Ndef(\keyboard).play;
Ndef(\keyboard).stop;
Ndef(\keyboard).gui

//////// Polyphony refactor for next iteration... but nah...
g=NPVoicer(Ndef(\polyKeyboard));
g.prime(\tone);
g.play
g.put(48,[\pitch,60]);
g.release(48,2); //second arg is release time, as gate doesn't really work...
g.put(49,[\pitch,63]);

g.release(49,2);
g.prime(\toggleSynth);*/