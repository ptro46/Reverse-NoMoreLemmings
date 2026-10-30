import AppKit

struct TestFailure: Error,CustomStringConvertible {let description:String}
func runTests(_ assets:Assets) throws {
    func require(_ condition: @autoclosure ()->Bool,_ message:String) throws {if !condition(){throw TestFailure(description:message)}}
    func checkRenderedHoles(_ before: [UInt8], _ engine: Engine, _ skill: Skill) throws {
        guard let image=TerrainBitmap.makeImage(pixels:engine.pixels,width:engine.width,height:engine.height) else {
            throw TestFailure(description:"Cannot render terrain")
        }
        // Composite the same CGImage as the game over an opaque black background.
        var rendered=[UInt8](repeating:0,count:engine.pixels.count)
        rendered.withUnsafeMutableBytes { bytes in
            let context=CGContext(data:bytes.baseAddress,width:engine.width,height:engine.height,bitsPerComponent:8,bytesPerRow:engine.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue|CGBitmapInfo.byteOrder32Big.rawValue)!
            context.setFillColor(CGColor(gray:0,alpha:1))
            let rect=CGRect(x:0,y:0,width:engine.width,height:engine.height)
            context.fill(rect);context.draw(image,in:rect)
        }
        let holes=before.indices.filter{before[$0] != 0 && engine.mask[$0]==0}
        try require(!holes.isEmpty,"No excavated pixels: \(skill.label)")
        for i in holes {
            try require(rendered[i*4]==0 && rendered[i*4+1]==0 && rendered[i*4+2]==0,"Excavated terrain still visible after rendering: \(skill.label)")
        }
        if let i=engine.mask.indices.first(where:{engine.mask[$0] != 0}) {
            try require(rendered[i*4]==engine.pixels[i*4] && rendered[i*4+1]==engine.pixels[i*4+1] && rendered[i*4+2]==engine.pixels[i*4+2],"Intact terrain changed color")
        }
    }
    try require(assets.catalog.levels.count==100,"Expected 100 levels")
    let e=try Engine(assets:assets)
    for level in assets.catalog.levels {
        try e.load(level.index)
        try require(level.objects.contains{$0.id==1},"Missing entrance \(level.index)")
        try require(level.objects.contains{$0.id==0},"Missing exit \(level.index)")
        for p in level.objects {try require(e.art(p) != nil,"Missing art \(level.index), object \(p.id)")}
        for _ in 0..<500 {e.step()}
        try require(e.released>0,"No spawn in \(level.index)")
        try require(e.released==e.active+e.saved+e.lost,"Population not conserved in \(level.index)")
        try require(e.mask.enumerated().allSatisfy{($0.element==0)==(e.pixels[$0.offset*4+3]==0)},"Terrain/collision mismatch")
    }
    try e.load(0);e.mask=[UInt8](repeating:0,count:e.width*e.height);e.pixels=[UInt8](repeating:0,count:e.width*e.height*4)
    for x in 20..<200 {e.brick(x:x,y:100,w:1)}
    let l=Lemming(id:0,x:60,y:60);e.lemmings=[l];e.released=1;e.spawnCountdown=10000
    for _ in 0..<35 {e.step()}
    try require(l.state == .walk && l.y==99,"Gravity and ground landing")
    let count=e.skills[Skill.dig.rawValue]
    try require(e.assign(.dig,to:l),"Digger assignment")
    try require(e.skills[7]==count-1,"Skill inventory")
    for _ in 0..<9 {e.step()}
    try require(!e.solid(l.x,100),"Digger must remove terrain")
    e.steel[100*e.width+100]=true;e.brick(x:100,y:100,w:1)
    try require(!e.clear(100,100) && e.solid(100,100),"Steel must resist destruction")
    let before=e.frame;e.paused=true;e.step();try require(e.frame==before,"Paused simulation must not advance")
    // A full unattended level exercises end-of-time and outcome accounting.
    try e.load(0);e.releaseRate=99
    for _ in 0..<5000 {e.step()}
    try require(e.finished,"Level must finish at timeout")
    // Exercise each skill against a controlled floor and wall, then a real exit trigger.
    for skill in Skill.allCases {
        try e.load(0)
        e.mask=[UInt8](repeating:0,count:e.width*e.height);e.pixels=[UInt8](repeating:0,count:e.width*e.height*4)
        for y in 100...120 {e.brick(x:50,y:y,w:100)}
        for y in 70...100 {e.brick(x:105,y:y,w:10)}
        let actor=Lemming(id:0,x:100,y:99);actor.state = .walk
        e.lemmings=[actor];e.released=1;e.spawnCountdown=10000
        try require(e.assign(skill,to:actor),"Skill rejected: \(skill.label)")
        if skill == .climb {try require(actor.climber,"Climber flag")}
        if skill == .float {try require(actor.floater,"Floater flag")}
        if skill == .bomb {
            for _ in 0..<86 {e.step()}
            try require(e.lost==1,"Bomber must retire and explode")
        } else if skill == .block {
            let walker=Lemming(id:1,x:94,y:99);walker.state = .walk;e.lemmings.append(walker);e.released+=1
            e.step();try require(walker.dir == -1,"Blocker must reverse approaching walkers")
        } else if [.build,.bash,.mine,.dig].contains(skill) {
            let before=e.mask
            for _ in 0..<17 {e.step()}
            try require(before != e.mask,"Skill must modify terrain: \(skill.label)")
            if [.bash,.mine,.dig].contains(skill) {try checkRenderedHoles(before,e,skill)}
        }
    }
    try e.load(0)
    if let exit=e.level.objects.first(where:{$0.id==0}),let art=e.art(exit) {
        let actor=Lemming(id:0,x:exit.x+art.triggerX*4,y:exit.y+art.triggerY*4);actor.state = .walk
        e.lemmings=[actor];e.released=1;e.spawnCountdown=10000;e.step()
        try require(e.saved==1 && actor.state == .exit,"Original exit trigger must rescue a walker")
    }
    print("PASS: 100 original levels, 50,000 simulation ticks, population accounting, collision pixels, spawning, landing, digger assignment, inventory, terrain destruction, visible excavations for basher/miner/digger, steel, pause, timeout, eight skills, blocker reversal and original exit trigger")
}
