a = FFVideoSource("encode_crf18.mkv").Subtitle("crf 18")
b = FFVideoSource("encode_crf22.mkv").Subtitle("crf 22")
c = FFVideoSource("original.mkv").Subtitle("source")

# side by side, then interleaved for frame stepping
StackHorizontal(a, b, c)
#Interleave(a, b, c)

ScriptClip("""Subtitle("frame " + String(current_frame))""")
ConvertToRGB32(matrix="Rec709")
Info()
