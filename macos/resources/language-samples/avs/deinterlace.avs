# Deinterlace a DV capture and resize it for the web
LoadPlugin("C:\Program Files\AviSynth\plugins\TIVTC.dll")
LoadPlugin("C:\Program Files\AviSynth\plugins\nnedi3.dll")

source = AviSource("capture.avi", audio=true)
source = source.AssumeBFF()

video = source.TFM(mode=1, pp=5).TDecimate(mode=1)
video = video.nnedi3(field=-2)
video = video.Spline36Resize(640, 480)

function Letterbox(clip c, int top, int bottom)
{
    return c.Crop(0, top, 0, -bottom).AddBorders(0, top, 0, bottom)
}

video = Letterbox(video, 8, 8)
video = video.ConvertToYV12()
AudioDub(video, source.GetChannel(1, 2))
