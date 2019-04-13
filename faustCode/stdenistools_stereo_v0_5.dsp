//--------------------------------------------------------------------------------------//
//--------------------------------StDenisTools v0.5-------------------------------------//
//
//-----------------------------BY ALAIN BONARDI - 2019----------------------------------//
//--------------------------------------------------------------------------------------//


import("stdfaust.lib");
import("stdenistools_common_v0_5.dsp");

//secondBlock and process specific to stereo output//

secondBlock = (((_, _, _, _) :> (_, _)), ((spat1, spat3, spat4) : ptodecoder : (ho.decoderStereo(1), _, _, _))) : ((si.bus(4) :> si.bus(2)), _, _, _) : (gain2, _, _, _);


process = firstBlock : (si.bus(7), secondBlock) : ((si.bus(4) :> _), si.bus(8));
