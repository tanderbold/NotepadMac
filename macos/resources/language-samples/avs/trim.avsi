/* Trims the credits and fades in and out */
function CutAndFade(clip c, int first, int last, int frames)
{
    c = c.Trim(first, last)
    c = c.FadeIn(frames).FadeOut(frames)
    return c
}

global fps_target = 25

clip = DirectShowSource("holiday.mp4", fps=29.97, convertfps=true)
clip = clip.ChangeFPS(fps_target)
clip = CutAndFade(clip, 120, 4800, 25)
clip = clip.Tweak(sat=1.1, bright=4, cont=1.05)
clip = clip.Subtitle("Summer 2009", x=20, y=20, first_frame=0, last_frame=100, size=32)
return clip
