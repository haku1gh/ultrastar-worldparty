{*
    UltraStar WorldParty - Karaoke Game

	UltraStar WorldParty is the legal property of its developers,
	whose names	are too numerous to list here. Please refer to the
	COPYRIGHT file distributed with this source distribution.

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program. Check "LICENSE" file. If not, see
	<http://www.gnu.org/licenses/>.
 *}

(*
 * Conversion of libavutil/channel_layout.h
 * avutil version 57.28.100 (FFmpeg 5.1)
 *)

type
  (**
   * An AVChannel represents a single audio channel.
   *)
  PAVChannel = ^TAVChannel;
  TAVChannel = (
    AV_CHAN_NONE = -1,
    AV_CHAN_FRONT_LEFT = 0,
    AV_CHAN_FRONT_RIGHT,
    AV_CHAN_FRONT_CENTER,
    AV_CHAN_LOW_FREQUENCY,
    AV_CHAN_BACK_LEFT,
    AV_CHAN_BACK_RIGHT,
    AV_CHAN_FRONT_LEFT_OF_CENTER,
    AV_CHAN_FRONT_RIGHT_OF_CENTER,
    AV_CHAN_BACK_CENTER,
    AV_CHAN_SIDE_LEFT,
    AV_CHAN_SIDE_RIGHT,
    AV_CHAN_TOP_CENTER,
    AV_CHAN_TOP_FRONT_LEFT,
    AV_CHAN_TOP_FRONT_CENTER,
    AV_CHAN_TOP_FRONT_RIGHT,
    AV_CHAN_TOP_BACK_LEFT,
    AV_CHAN_TOP_BACK_CENTER,
    AV_CHAN_TOP_BACK_RIGHT,
    (* Stereo downmix. *)
    AV_CHAN_STEREO_LEFT = 29,
    AV_CHAN_STEREO_RIGHT,
    AV_CHAN_WIDE_LEFT,
    AV_CHAN_WIDE_RIGHT,
    AV_CHAN_SURROUND_DIRECT_LEFT,
    AV_CHAN_SURROUND_DIRECT_RIGHT,
    AV_CHAN_LOW_FREQUENCY_2,
    AV_CHAN_TOP_SIDE_LEFT,
    AV_CHAN_TOP_SIDE_RIGHT,
    AV_CHAN_BOTTOM_FRONT_CENTER,
    AV_CHAN_BOTTOM_FRONT_LEFT,
    AV_CHAN_BOTTOM_FRONT_RIGHT,
    (* Channel is empty can be safely skipped. *)
    AV_CHAN_UNUSED = $200,
    (* Channel contains data, but its position is unknown. *)
    AV_CHAN_UNKNOWN = $300,
    (* Range of channels between AV_CHAN_AMBISONIC_BASE and AV_CHAN_AMBISONIC_END
       represent Ambisonic components using the ACN system. *)
    AV_CHAN_AMBISONIC_BASE = $400,
    AV_CHAN_AMBISONIC_END  = $7ff
  );

  (**
   * Specify the order of the channels in an AVChannelLayout.
   *)
  TAVChannelOrder = (
    (* Only the channel count is specified, without any further information
       about the channel order. *)
    AV_CHANNEL_ORDER_UNSPEC,
    (* The native channel order, i.e. the channels are in the same order in
       which they are defined in the AVChannel enum. *)
    AV_CHANNEL_ORDER_NATIVE,
    (* The channel order does not correspond to any other predefined order and
       is stored as an explicit map. *)
    AV_CHANNEL_ORDER_CUSTOM,
    (* The audio is represented as the decomposition of the sound field into
       spherical harmonics. *)
    AV_CHANNEL_ORDER_AMBISONIC
  );

  (**
   * An AVChannelCustom defines a single channel within a custom order layout
   *
   * Unlike most structures in FFmpeg, sizeof(AVChannelCustom) is a part of the
   * public ABI.
   *)
  PAVChannelCustom = ^TAVChannelCustom;
  TAVChannelCustom = record
    id: TAVChannel;
    name: array[0..15] of AnsiChar;
    opaque: pointer;
  end;

  (**
   * An AVChannelLayout holds information about the channel layout of audio data.
   *
   * A channel layout here is defined as a set of channels ordered in a specific
   * way (unless the channel order is AV_CHANNEL_ORDER_UNSPEC, in which case an
   * AVChannelLayout carries only the channel count).
   * All orders may be treated as if they were AV_CHANNEL_ORDER_UNSPEC by
   * ignoring everything but the channel count, as long as av_channel_layout_check()
   * considers they are valid.
   *
   * Unlike most structures in FFmpeg, sizeof(AVChannelLayout) is a part of the
   * public ABI and may be used by the caller. E.g. it may be allocated on stack
   * or embedded in caller-defined structs.
   *
   * AVChannelLayout can be initialized as follows:
   * - default initialization with {0}, followed by setting all used fields
   *   correctly;
   * - by assigning one of the predefined AV_CHANNEL_LAYOUT_* initializers;
   * - with a constructor function, such as av_channel_layout_default(),
   *   av_channel_layout_from_mask() or av_channel_layout_from_string().
   *
   * The channel layout must be unitialized with av_channel_layout_uninit()
   *)
  PAVChannelLayout = ^TAVChannelLayout;
  TAVChannelLayout = record
    (**
     * Channel order used in this layout.
     * This is a mandatory field.
     *)
    order: TAVChannelOrder;

    (**
     * Number of channels in this layout. Mandatory field.
     *)
    nb_channels: cint;

    (**
     * Details about which channels are present in this layout.
     * For AV_CHANNEL_ORDER_UNSPEC, this field is undefined and must not be
     * used.
     *)
    u: record
      case integer of
        (**
         * This member must be used for AV_CHANNEL_ORDER_NATIVE, and may be used
         * for AV_CHANNEL_ORDER_AMBISONIC to signal non-diegetic channels.
         * It is a bitmask, where the position of each set bit means that the
         * AVChannel with the corresponding value is present.
         *)
        0: (mask: cuint64);
        (**
         * This member must be used when the channel order is
         * AV_CHANNEL_ORDER_CUSTOM. It is a nb_channels-sized array, with each
         * element signalling the presence of the AVChannel with the
         * corresponding value in map[i].id.
         *)
        1: (map: PAVChannelCustom);
    end;

    (**
     * For some private data of the user.
     *)
    opaque: pointer;
  end;

(**
 * Initialize a native channel layout from a bitmask indicating which channels
 * are present.
 *
 * @param channel_layout the layout structure to be initialized
 * @param mask bitmask describing the channel layout
 *
 * @return 0 on success
 *         AVERROR(EINVAL) for invalid mask values
 *)
function av_channel_layout_from_mask(channel_layout: PAVChannelLayout; mask: cuint64): cint;
  cdecl; external av__util;

(**
 * Initialize a channel layout from a given string description.
 *
 * @return 0 on success
 *         AVERROR(EINVAL) if the string is not valid or not a known layout
 *)
function av_channel_layout_from_string(channel_layout: PAVChannelLayout; str: {const} PAnsiChar): cint;
  cdecl; external av__util;

(**
 * Get the default channel layout for a given number of channels.
 *
 * @param ch_layout the layout structure to be initialized
 * @param nb_channels number of channels
 *)
procedure av_channel_layout_default(ch_layout: PAVChannelLayout; nb_channels: cint);
  cdecl; external av__util;

(**
 * Free any allocated data in the channel layout and reset the channel
 * count to 0.
 *
 * @param channel_layout the layout structure to be uninitialized
 *)
procedure av_channel_layout_uninit(channel_layout: PAVChannelLayout);
  cdecl; external av__util;

(**
 * Make a copy of a channel layout. This differs from just assigning src to dst
 * in that it allocates and copies the map for AV_CHANNEL_ORDER_CUSTOM.
 *
 * @note the destination channel_layout will be always uninitialized before copy.
 *
 * @param dst destination channel layout
 * @param src source channel layout
 * @return 0 on success, a negative AVERROR on error.
 *)
function av_channel_layout_copy(dst: PAVChannelLayout; src: {const} PAVChannelLayout): cint;
  cdecl; external av__util;

(**
 * Get a human-readable string describing the channel layout properties.
 * The string will be in the same format that is accepted by
 * av_channel_layout_from_string(), allowing to rebuild the same
 * channel layout, except for opaque pointers.
 *
 * @param channel_layout channel layout to be described
 * @param buf buffer to write the string to
 * @param buf_size size of the output buffer
 * @return amount of bytes needed to hold the output string, or a negative AVERROR
 *         on failure. If the returned value is bigger than buf_size, then the
 *         string was truncated.
 *)
function av_channel_layout_describe(channel_layout: {const} PAVChannelLayout;
                                    buf: PAnsiChar; buf_size: size_t): cint;
  cdecl; external av__util;

(**
 * Check whether a channel layout is valid, i.e. can possibly describe audio
 * data.
 *
 * @param channel_layout input channel layout
 * @return 1 if channel_layout is valid, 0 otherwise.
 *)
function av_channel_layout_check(channel_layout: {const} PAVChannelLayout): cint;
  cdecl; external av__util;

(**
 * Check whether two channel layouts are semantically the same, i.e. the same
 * channels are present on the same positions in both.
 *
 * @return 0 if chl and chl1 are equal, 1 if they are not equal. A negative
 *         AVERROR code if one or both are invalid.
 *)
function av_channel_layout_compare(chl: {const} PAVChannelLayout; chl1: {const} PAVChannelLayout): cint;
  cdecl; external av__util;
