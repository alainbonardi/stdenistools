//--------------------------------------------------------------------------------------//
//--------------------------------StDenisTools v0.5-------------------------------------//
//
//-----------------------------BY ALAIN BONARDI - 2019----------------------------------//
//--------------------------------------------------------------------------------------//

//Maximum delay size in samples is now 1048576 (and no longer 2097152)
//that is more than 21 seconds at 48 KHz

import("stdfaust.lib");
import("stdenistools_common_v0_5.dsp");

//secondBlock and process specific to quadri output//

secondBlock = (_, _, _, _, ((spat1, spat3, spat4) : ptodecoder : (mydecoder(1, 4), _, _, _))) : ((si.bus(8) :> si.bus(4)), _, _, _) : (gain4, _, _, _);


process = firstBlock : (si.bus(7), secondBlock) : ((si.bus(4) :> _), si.bus(10));
