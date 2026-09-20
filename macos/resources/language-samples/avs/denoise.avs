SetMemoryMax(1024)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

LWLibavVideoSource("tape.mkv")
AssumeTFF()
QTGMC(Preset="Slower", EZDenoise=2.0, NoisePreset="Slow")
SelectEven()

super = MSuper(pel=2, sharp=1)
bv = MAnalyse(super, isb=true, delta=1, overlap=4)
fv = MAnalyse(super, isb=false, delta=1, overlap=4)
MDegrain1(super, bv, fv, thSAD=400)

LimitedSharpenFaster(strength=80)
Prefetch(4)
