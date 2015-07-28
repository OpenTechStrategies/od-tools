#!/usr/bin/perl
#
# Extract the audio from the .mp4 files in the current directory and save as a low quality mono mp3 files in mp3 sub-directory
#
for( glob "*.mp4" ) {
	s/.mp4$//;
	qx "ffmpeg -i \"$_.mp4\" -acodec libmp3lame -ab 32k -ar 11025 -ac 1 \"mp3/$_.mp3\"";
}
