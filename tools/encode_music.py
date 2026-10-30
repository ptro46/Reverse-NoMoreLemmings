"""Encode the original rendered WAVs for native playback using FFmpeg."""
from pathlib import Path
import subprocess,shutil,json,wave,hashlib
root=Path(__file__).resolve().parents[1];folder=root/'Assets/music'
ffmpeg=shutil.which('ffmpeg')
if not ffmpeg:raise SystemExit('FFmpeg is required to create M4A copies. Original WAVs are unaffected.')
report=[]
for source in sorted(folder.glob('tune*.wav')):
    target=source.with_suffix('.m4a')
    subprocess.run([ffmpeg,'-v','error','-y','-i',str(source),'-c:a','aac','-b:a','160k','-movflags','+faststart',str(target)],check=True)
    with wave.open(str(source),'rb') as audio:
        report.append({'name':source.stem,'sample_rate':audio.getframerate(),'channels':audio.getnchannels(),'duration_seconds':round(audio.getnframes()/audio.getframerate(),3),'wav_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'native_file':target.name})
(folder/'manifest.json').write_text(json.dumps(report,indent=2)+'\n')
print('Encoded',len(report),'tracks')
