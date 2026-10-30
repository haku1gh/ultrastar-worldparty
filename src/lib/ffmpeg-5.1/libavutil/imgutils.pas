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

 (**
 * Translation of libavutil/imgutils.h (only the functions used by USDX).
 * This file is included by avutil.pas.
 *)

(**
 * Return the size in bytes of the amount of data required to store an
 * image with the given parameters.
 *
 * @param pix_fmt the pixel format of the image
 * @param width the width of the image in pixels
 * @param height the height of the image in pixels
 * @param align the assumed linesize alignment
 * @return the buffer size in bytes, a negative error code in case of failure
 *)
function av_image_get_buffer_size(pix_fmt: TAVPixelFormat; width: cint; height: cint; align: cint): cint;
  cdecl; external av__util;

(**
 * Setup the data pointers and linesizes based on the specified image
 * parameters and the provided array.
 *
 * @param dst_data      data pointers to be filled in (array of 4 pointers)
 * @param dst_linesize  linesizes for the image in dst_data to be filled in (array of 4 ints)
 * @param src           buffer which will contain or contains the actual image data, can be NULL
 * @param pix_fmt       the pixel format of the image
 * @param width         the width of the image in pixels
 * @param height        the height of the image in pixels
 * @param align         the value used in src for linesize alignment
 * @return the size in bytes required for src, a negative error code
 *         in case of failure
 *)
function av_image_fill_arrays(dst_data: Pointer; dst_linesize: Pcint; src: Pcuint8;
                              pix_fmt: TAVPixelFormat; width: cint; height: cint;
                              align: cint): cint;
  cdecl; external av__util;
