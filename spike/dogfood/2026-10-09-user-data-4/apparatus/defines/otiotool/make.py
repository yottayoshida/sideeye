import sys
import opentimelineio as otio

tl = otio.schema.Timeline(name="cut")
tr = otio.schema.Track(name="V1", kind=otio.schema.TrackKind.Video)
tl.tracks.append(tr)
for i in range(3):
    c = otio.schema.Clip(
        name=f"clip{i}",
        media_reference=otio.schema.ExternalReference(target_url=f"/media/take{i}.mov"),
        source_range=otio.opentime.TimeRange(otio.opentime.RationalTime(0, 24), otio.opentime.RationalTime(48, 24)),
    )
    tr.append(c)
otio.adapters.write_to_file(tl, sys.argv[1])
