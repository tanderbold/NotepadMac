# Replace the soundtrack and normalise it
v = ImageSource("frames\%06d.png", start=1, end=2400, fps=24)
a = WavSource("score.wav")
a = a.ResampleAudio(48000).Normalize(0.98)
a = a.DelayAudio(0.250)
AudioDub(v, a)
EnsureVBRMP3Sync()
ConvertAudioTo16bit()
Trim(0, FrameCount() - 1)
