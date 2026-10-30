import Foundation

enum State: String { case walk,fall,float,climb,hoist,bomb,block,build,bash,mine,dig,exit,splat,dead }
final class Lemming {
    let id: Int
    var x,y,dir: Int
    var state: State = .fall
    var tick=0, fallDistance=0, steps=0, bombTimer=0
    var climber=false, floater=false
    init(id: Int,x: Int,y: Int,dir: Int=1) {self.id=id;self.x=x;self.y=y;self.dir=dir}
    func set(_ new: State) {state=new;tick=0}
}
final class Engine {
    let assets: Assets; let width: Int; let height: Int
    var level: Level
    var pixels: [UInt8] = [], mask: [UInt8] = [], steel: [Bool] = []
    var lemmings: [Lemming] = []
    var skills: [Int] = []
    var frame=0, released=0, saved=0, lost=0, releaseRate=1
    var timeLeft=0, spawnCountdown=25
    var paused=false, fast=false, nuking=false, finished=false
    var changed=true, sound: ((String)->Void)?
    var traps: [Int:Int] = [:]
    init(assets: Assets, index: Int=0) throws {
        self.assets=assets;width=assets.catalog.width;height=assets.catalog.height
        level=assets.catalog.levels[index]
        try load(index)
    }
    func load(_ index: Int) throws {
        let next=assets.catalog.levels[max(0,min(index,assets.catalog.levels.count-1))]
        let newPixels=try assets.rgba(String(format:"levels/%03d.png",next.index))
        let newMask=Array(try Data(contentsOf:assets.root.appendingPathComponent(String(format:"game/levels/%03d.mask",next.index))))
        guard newPixels.count==width*height*4 && newMask.count==width*height else {throw NSError(domain:"Invalid level",code:index)}
        level=next;pixels=newPixels;mask=newMask;steel=[Bool](repeating:false,count:mask.count)
        for r in level.steel {
            for y in max(0,r.y)..<max(0,min(height,r.y+r.height)) {
                for x in max(0,r.x)..<max(0,min(width,r.x+r.width)) {steel[y*width+x]=true}
            }
        }
        skills=next.skills;lemmings=[];frame=0;released=0;saved=0;lost=0
        releaseRate=next.releaseRate;timeLeft=next.minutes*60*17;spawnCountdown=25
        paused=false;nuking=false;finished=false;changed=true;traps=[:]
    }
    func solid(_ x: Int,_ y: Int)->Bool { x>=0 && x<width && y>=0 && y<height && mask[y*width+x] != 0 }
    func hard(_ x: Int,_ y: Int)->Bool { x>=0 && x<width && y>=0 && y<height && steel[y*width+x] }
    @discardableResult func clear(_ x: Int,_ y: Int)->Bool {
        guard x>=0 && x<width && y>=0 && y<height else{return false}
        let i=y*width+x
        guard !steel[i],mask[i] != 0 else{return false}
        mask[i]=0
        // CoreGraphics expects premultiplied RGBA: transparent pixels must
        // also have zero RGB, otherwise their old color remains in the image.
        let pixel=i*4
        pixels[pixel]=0;pixels[pixel+1]=0;pixels[pixel+2]=0;pixels[pixel+3]=0
        changed=true;return true
    }
    @discardableResult func carve(x: Int,y: Int,w: Int,h: Int)->Int {
        var count=0
        for yy in y..<y+h {for xx in x..<x+w {if clear(xx,yy){count+=1}}}
        return count
    }
    func brick(x: Int,y: Int,w: Int=6) {
        let color=assets.catalog.styles[level.style].palette[7]
        for xx in x..<x+w where xx>=0 && xx<width && y>=0 && y<height {
            let i=y*width+xx
            if mask[i]==0 {
                mask[i]=1;pixels[i*4]=UInt8(color[0]);pixels[i*4+1]=UInt8(color[1]);pixels[i*4+2]=UInt8(color[2]);pixels[i*4+3]=255;changed=true
            }
        }
    }
    var active: Int { lemmings.filter{ ![State.dead,.exit,.splat].contains($0.state) }.count }
    var won: Bool { saved>=level.required }
    func retire(_ l: Lemming, rescued: Bool=false, splat: Bool=false) {
        guard ![State.dead,.exit,.splat].contains(l.state) else{return}
        if rescued {saved+=1;l.set(.exit);sound?("exit")}
        else {lost+=1;l.set(splat ? .splat:.dead);sound?(splat ? "splat":"die")}
    }
    func assign(_ skill: Skill,to l: Lemming)->Bool {
        guard !finished,skills[skill.rawValue]>0,![State.dead,.exit,.splat].contains(l.state) else{return false}
        switch skill {
        case .climb: guard !l.climber else{return false};l.climber=true
        case .float: guard !l.floater else{return false};l.floater=true
        case .bomb: guard l.bombTimer==0 else{return false};l.bombTimer=5*17
        case .block: guard l.state == .walk else{return false};l.set(.block)
        case .build: guard [.walk,.build].contains(l.state) else{return false};l.steps=0;l.set(.build)
        case .dig: guard [.walk,.build].contains(l.state),solid(l.x,l.y+1),!hard(l.x,l.y+1) else{return false};l.set(.dig)
        case .bash:
            guard [.walk,.build].contains(l.state),!oneWayStops(l),!hard(l.x+l.dir*8,l.y-5) else{return false};l.set(.bash)
        case .mine:
            guard [.walk,.build].contains(l.state),!oneWayStops(l),!hard(l.x+l.dir*4,l.y+1) else{return false};l.set(.mine)
        }
        skills[skill.rawValue]-=1;sound?("assign");return true
    }
    func oneWayStops(_ l: Lemming)->Bool {
        for p in level.objects {
            guard let art=art(p),[7,8].contains(art.sound),inTrigger(l,p,art) else {continue}
            if (art.sound==7 && l.dir<0) || (art.sound==8 && l.dir>0) {return true}
        }
        return false
    }
    func art(_ p: Placement)->ObjectArt? {
        let list=assets.catalog.styles[level.style].objects
        return p.id>=0 && p.id<list.count ? list[p.id]:nil
    }
    func inTrigger(_ l: Lemming,_ p: Placement,_ art: ObjectArt)->Bool {
        let x=p.x+art.triggerX*4,y=p.y+art.triggerY*4
        return l.x>=x && l.x<x+art.triggerWidth*4 && l.y>=y && l.y<y+art.triggerHeight*4
    }
    func hazards(_ l: Lemming) {
        for (i,p) in level.objects.enumerated() {
            guard let a=art(p),inTrigger(l,p,a) else{continue}
            if p.id==0 && l.state != .fall && l.state != .float {retire(l,rescued:true);return}
            // Trigger low nibble: 4 water, 7/8 one-way, 9 steel. Traps have nonzero activation code.
            if a.trigger != 0 && [4,5,6].contains(a.sound) {
                if [4,5].contains(a.sound) {retire(l);sound?("trap")}
                else if (traps[i] ?? 0)==0 {retire(l);traps[i]=max(8,a.frames.count);sound?("trap")};return
            }
        }
    }
    func explode(_ l: Lemming) {
        for dy in -16...7 {for dx in -16...16 where dx*dx+(dy+4)*(dy+4)<17*17 {_ = clear(l.x+dx,l.y+dy)}}
        sound?("explode");retire(l)
    }
    func step() {
        guard !paused,!finished else{return}
        frame+=1;timeLeft-=1
        traps=traps.mapValues{max(0,$0-1)}
        if nuking {
            if frame%2==0,let l=lemmings.first(where:{$0.bombTimer==0 && ![State.dead,.exit,.splat].contains($0.state)}) {l.bombTimer=5*17}
        } else if released<level.total {
            spawnCountdown-=1
            if spawnCountdown<=0 {
                let entrances=level.objects.filter{$0.id==1}
                if !entrances.isEmpty {
                    let p=entrances[released%entrances.count]
                    lemmings.append(Lemming(id:released,x:p.x+24,y:p.y+14));released+=1
                    spawnCountdown=max(4,(99-releaseRate)/2+4)
                    if released==1 {sound?("letsgo")}
                } else {released=level.total}
            }
        }
        for l in lemmings {
            if l.state == .dead {continue}
            if l.state == .splat || l.state == .exit {l.tick+=1;if l.tick>=16 {l.state = .dead};continue}
            if l.bombTimer>0 {l.bombTimer-=1;if l.bombTimer==0 {explode(l);continue}}
            l.tick+=1
            if l.y>=height+10 || l.x<16 || l.x>=width-16 {retire(l);continue}
            hazards(l)
            if [.dead,.exit,.splat].contains(l.state){continue}
            switch l.state {
            case .fall,.float:
                let speed=l.state == .float ? 2:min(3,1+l.fallDistance/4)
                var landed=false
                for _ in 0..<speed {
                    if solid(l.x,l.y+1) {landed=true;break}
                    l.y+=1;l.fallDistance+=1
                }
                if landed {
                    if l.fallDistance>60 && !l.floater {retire(l,splat:true)}
                    else {l.set(.walk);l.fallDistance=0}
                } else if l.floater && l.fallDistance>16 && l.state != .float {l.set(.float)}
            case .walk:
                if !solid(l.x,l.y+1) {
                    var landing: Int?=nil
                    for d in 1...3 {if solid(l.x,l.y+d){landing=d-1;break}}
                    if let d=landing {l.y+=d} else {l.set(.fall);l.fallDistance=0;continue}
                }
                if lemmings.contains(where:{$0 !== l && $0.state == .block && abs($0.y-l.y)<5 && abs($0.x-l.x)<7 && ($0.x-l.x)*l.dir>0}) {l.dir = -l.dir;continue}
                let nx=l.x+l.dir
                if solid(nx,l.y) {
                    var rise: Int?=nil
                    for h in 1...6 {if !solid(nx,l.y-h){rise=h;break}}
                    if let h=rise {l.x=nx;l.y-=h}
                    else if l.climber {l.set(.climb)} else {l.dir = -l.dir}
                } else {l.x=nx}
            case .climb:
                if solid(l.x,l.y-11) {l.dir = -l.dir;l.x+=l.dir;l.set(.fall);l.fallDistance=0}
                else if !solid(l.x+l.dir,l.y-6) {l.set(.hoist)} else {l.y-=1}
            case .hoist:
                if l.tick%2==0 {l.y-=1}
                if l.tick>=8 {l.x+=l.dir*2;l.set(.walk)}
            case .block:
                if !solid(l.x,l.y+1) {l.set(.fall);l.fallDistance=0}
            case .build:
                if l.tick%16==9 {
                    if solid(l.x+l.dir*4,l.y-10) || l.y<5 {l.dir = -l.dir;l.set(.walk);continue}
                    brick(x:l.dir>0 ? l.x:l.x-5,y:l.y)
                }
                if l.tick%16==0 {
                    l.x+=l.dir*2;l.y-=1;l.steps+=1
                    if l.steps>=12 {l.set(.walk)}
                }
            case .dig:
                if l.tick%8==0 {
                    if (-4...4).contains(where:{hard(l.x+$0,l.y+1)}) {l.set(.walk);continue}
                    let removed=carve(x:l.x-4,y:l.y,w:9,h:2)
                    l.y+=1
                    if removed==0 && !solid(l.x,l.y+1) {l.set(.fall);l.fallDistance=0}
                }
            case .bash:
                if l.tick%4==0 {
                    let front=l.x+l.dir*6
                    if hard(front,l.y-4) || oneWayStops(l) {l.dir = -l.dir;l.set(.walk);continue}
                    let removed=carve(x:l.dir>0 ? l.x:l.x-8,y:l.y-9,w:9,h:10)
                    l.x+=l.dir
                    if !solid(l.x,l.y+1) {l.set(.fall);l.fallDistance=0}
                    else if removed==0 {l.set(.walk)}
                }
            case .mine:
                if l.tick%8==0 {
                    if hard(l.x+l.dir*4,l.y+1) || oneWayStops(l) {l.dir = -l.dir;l.set(.walk);continue}
                    let removed=carve(x:l.dir>0 ? l.x-2:l.x-7,y:l.y-8,w:10,h:11)
                    l.x+=l.dir*2;l.y+=1
                    if removed==0 {l.set(.fall);l.fallDistance=0}
                }
            default:break
            }
        }
        if timeLeft<=0 || ((released>=level.total || nuking) && active==0) {
            finished=true
            if won {UserDefaults.standard.set(true,forKey:"completed.\(level.index)")}
        }
    }
}
