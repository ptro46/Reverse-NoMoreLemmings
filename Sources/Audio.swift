import AVFoundation
import Foundation

final class Audio {
    let root:URL
    var effects=true, musicEnabled=true
    var voices:[AVAudioPlayer]=[]
    var music:AVAudioPlayer?
    init(root:URL){self.root=root}
    func play(_ name:String) {
        guard effects else{return}
        let files=["assign":"BasicFX.wav","letsgo":"BasicFX_020b0.wav","splat":"BasicFX_056c2.wav","explode":"BasicFX_039e2.wav","die":"BasicFX_04162.wav","exit":"BasicFX_08142.wav","trap":"FullFX_01456.wav"]
        guard let file=files[name],let p=try? AVAudioPlayer(contentsOf:root.appendingPathComponent("audio/"+file)) else{return}
        voices.removeAll{!$0.isPlaying};voices.append(p);p.volume=0.65;p.play()
    }
    func tune(_ index:Int) {
        music?.stop();music=nil
        guard musicEnabled,let p=try? AVAudioPlayer(contentsOf:root.appendingPathComponent("music/tune\([1,2,3,5,6,4][index%6]).m4a")) else{return}
        music=p;p.numberOfLoops = -1;p.volume=0.4;p.play()
    }
}
