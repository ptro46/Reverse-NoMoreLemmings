import AppKit

enum TerrainBitmap {
    static func makeImage(pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        let data=Data(pixels) as CFData
        guard let provider=CGDataProvider(data:data) else{return nil}
        return CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue|CGBitmapInfo.byteOrder32Big.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)
    }
}

final class GameView: NSView {
    let engine: Engine
    var camera: CGFloat = -1
    var selection: Skill = .dig
    var hover: Lemming?
    var pointer = NSPoint(x:-1,y:-1)
    var onChange: (()->Void)?
    var terrainImage: NSImage?
    var dragging=false
    override var isFlipped: Bool {true}
    override var acceptsFirstResponder: Bool {true}
    var scale: CGFloat { max(1,floor(min(bounds.width/320,(bounds.height-64)/168))) }
    var visibleWidth: CGFloat {min(CGFloat(engine.width),bounds.width/scale)}
    var originY: CGFloat {max(12,(bounds.height-64-CGFloat(engine.height)*scale)/2)}
    var worldRect: NSRect {NSRect(x:0,y:originY,width:bounds.width,height:CGFloat(engine.height)*scale)}
    var miniRect: NSRect {NSRect(x:20,y:bounds.height-42,width:bounds.width-40,height:24)}
    init(engine: Engine) {self.engine=engine;super.init(frame:.zero);camera = -1}
    required init?(coder:NSCoder){fatalError()}
    func resetCamera() {camera=CGFloat(engine.level.cameraX)+160-visibleWidth/2;clampCamera();hover=nil;terrainImage=nil}
    func clampCamera() {camera=max(0,min(CGFloat(engine.width)-visibleWidth,camera))}
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect:bounds,options:[.activeInKeyWindow,.mouseMoved,.mouseEnteredAndExited,.inVisibleRect],owner:self,userInfo:nil))
    }
    func terrain() -> NSImage? {
        if !engine.changed,let im=terrainImage{return im}
        guard let cg=TerrainBitmap.makeImage(pixels:engine.pixels,width:engine.width,height:engine.height) else{return nil}
        let image=NSImage(cgImage:cg,size:NSSize(width:engine.width,height:engine.height));terrainImage=image;engine.changed=false;return image
    }
    func drawImage(_ im:NSImage?,x:CGFloat,y:CGFloat,w:CGFloat,h:CGFloat,alpha:CGFloat=1,flip:Bool=false) {
        guard let im=im else{return}
        let dest=NSRect(x:(x-camera)*scale,y:originY+y*scale,width:w*scale,height:h*scale)
        guard dest.intersects(worldRect) else{return}
        im.draw(in:dest,from:.zero,operation:.sourceOver,fraction:alpha,respectFlipped:true,hints:[.interpolation:NSImageInterpolation.none])
    }
    func label(_ s:String,at p:NSPoint,size:CGFloat=13,color:NSColor = .white,bold:Bool=false) {
        s.draw(at:p,withAttributes:[.font:bold ? NSFont.monospacedSystemFont(ofSize:size,weight:.bold):NSFont.monospacedSystemFont(ofSize:size,weight:.regular),.foregroundColor:color])
    }
    override func draw(_ dirtyRect:NSRect) {
        NSColor(calibratedRed:0.035,green:0.045,blue:0.065,alpha:1).setFill();bounds.fill()
        if camera<0 {camera=CGFloat(engine.level.cameraX)+160-visibleWidth/2}
        clampCamera();NSColor.black.setFill();worldRect.fill()
        NSGraphicsContext.saveGraphicsState();worldRect.clip();NSGraphicsContext.current?.imageInterpolation = .none
        // Original object flag bit 15 places art behind terrain.
        func objects(behind:Bool) {
            for (i,p) in engine.level.objects.enumerated() where (p.flags&0x8000 != 0)==behind {
                guard let a=engine.art(p),!a.frames.isEmpty else{continue}
                let frame:Int
                if p.id==1 {frame=min(a.frames.count-1,max(0,engine.frame/2))}
                else if (engine.traps[i] ?? 0)>0 {frame=(a.frames.count-(engine.traps[i] ?? 0))%a.frames.count}
                else {frame=a.kind==1 ? 0:(engine.frame/2)%a.frames.count}
                drawImage(engine.assets.image(a.frames[max(0,frame)]),x:CGFloat(p.x),y:CGFloat(p.y),w:CGFloat(a.width),h:CGFloat(a.height))
            }
        }
        objects(behind:true)
        drawImage(terrain(),x:0,y:0,w:CGFloat(engine.width),h:CGFloat(engine.height))
        objects(behind:false)
        hover=nearest(pointer)
        for l in engine.lemmings where l.state != .dead {
            let name=l.state.rawValue
            guard let s=engine.assets.catalog.sprites[name] else{continue}
            let direction=l.dir>0 ? 0:1
            let list=s.frames[direction];guard !list.isEmpty else{continue}
            let i=(l.tick)%list.count
            drawImage(engine.assets.image(list[i]),x:CGFloat(l.x-8),y:CGFloat(l.y-s.height+1),w:CGFloat(s.width),h:CGFloat(s.height))
            if l.bombTimer>0 {label("\((l.bombTimer+16)/17)",at:NSPoint(x:CGFloat(l.x-2)*scale-camera*scale,y:originY+CGFloat(l.y-s.height-8)*scale),size:max(11,scale*5),color:.systemYellow,bold:true)}
        }
        if let l=hover {
            NSColor.systemYellow.setStroke();let r=NSRect(x:CGFloat(l.x-7)*scale-camera*scale,y:originY+CGFloat(l.y-12)*scale,width:14*scale,height:16*scale)
            let path=NSBezierPath(roundedRect:r,xRadius:3,yRadius:3);path.lineWidth=1.5;path.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        label("\(selection.symbol) \(selection.label) · clic sur un lemming",at:NSPoint(x:20,y:bounds.height-63),size:12,color:.secondaryLabelColor)
        let r=miniRect;NSColor.black.setFill();NSBezierPath(roundedRect:r,xRadius:4,yRadius:4).fill()
        terrainImage?.draw(in:r,from:.zero,operation:.sourceOver,fraction:0.75,respectFlipped:true,hints:[.interpolation:NSImageInterpolation.none])
        for l in engine.lemmings where l.state != .dead {
            NSColor.systemGreen.setFill();NSRect(x:r.minX+CGFloat(l.x)/CGFloat(engine.width)*r.width,y:r.minY+CGFloat(l.y)/CGFloat(engine.height)*r.height,width:2,height:2).fill()
        }
        NSColor.white.setStroke();let view=NSBezierPath(rect:NSRect(x:r.minX+camera/CGFloat(engine.width)*r.width,y:r.minY,width:visibleWidth/CGFloat(engine.width)*r.width,height:r.height));view.lineWidth=1;view.stroke()
        if engine.finished {overlay(engine.won ? "Niveau réussi !":"Fin de partie",sub:"\(engine.saved) sauvés · objectif \(engine.level.required) — Entrée : \(engine.won ? "niveau suivant":"réessayer")")}
        else if engine.paused {overlay("Pause",sub:"Espace pour reprendre")}
        else if engine.frame<24 {label(engine.level.title,at:NSPoint(x:22,y:originY+16),size:18,color:.white,bold:true)}
    }
    func overlay(_ title:String,sub:String) {
        let r=NSRect(x:bounds.midX-260,y:worldRect.midY-50,width:520,height:100)
        NSColor(calibratedWhite:0.05,alpha:0.92).setFill();NSBezierPath(roundedRect:r,xRadius:12,yRadius:12).fill()
        label(title,at:NSPoint(x:r.minX+22,y:r.minY+18),size:23,color:engine.won ? .systemGreen:.white,bold:true)
        label(sub,at:NSPoint(x:r.minX+22,y:r.minY+59),size:11,color:.lightGray)
    }
    func nearest(_ pt:NSPoint)->Lemming? {
        guard worldRect.contains(pt) else{return nil}
        let wx=pt.x/scale+camera,wy=(pt.y-originY)/scale
        return engine.lemmings.filter{![State.dead,.exit,.splat].contains($0.state) && abs(CGFloat($0.x)-wx)<9 && abs(CGFloat($0.y)-5-wy)<12}.min{abs(CGFloat($0.x)-wx)<abs(CGFloat($1.x)-wx)}
    }
    override func mouseMoved(with event:NSEvent) {pointer=convert(event.locationInWindow,from:nil);needsDisplay=true}
    override func mouseExited(with event:NSEvent) {pointer=NSPoint(x:-1,y:-1);needsDisplay=true}
    override func mouseDown(with event:NSEvent) {
        window?.makeFirstResponder(self);pointer=convert(event.locationInWindow,from:nil)
        if miniRect.contains(pointer) {dragging=true;moveMini(pointer);return}
        if let l=nearest(pointer) {_ = engine.assign(selection,to:l);onChange?()};needsDisplay=true
    }
    func moveMini(_ p:NSPoint) {camera=(p.x-miniRect.minX)/miniRect.width*CGFloat(engine.width)-visibleWidth/2;clampCamera();needsDisplay=true}
    override func mouseDragged(with event:NSEvent) {if dragging{moveMini(convert(event.locationInWindow,from:nil))}}
    override func mouseUp(with event:NSEvent) {dragging=false}
    override func rightMouseDown(with event:NSEvent) {selection=Skill(rawValue:(selection.rawValue+1)%8)!;onChange?();needsDisplay=true}
    override func scrollWheel(with event:NSEvent) {camera+=(event.scrollingDeltaX != 0 ? event.scrollingDeltaX:event.scrollingDeltaY)*3/scale;clampCamera();needsDisplay=true}
    override func keyDown(with event:NSEvent) {
        if let c=event.charactersIgnoringModifiers {
            if let n=Int(c),n>=1,n<=8 {selection=Skill(rawValue:n-1)!}
            else if c==" " {engine.paused.toggle()}
            else if c.lowercased()=="f" {engine.fast.toggle()}
            else if c.lowercased()=="r" {try? engine.load(engine.level.index);resetCamera()}
            else if c=="\r" && engine.finished {try? engine.load(engine.won ? min(99,engine.level.index+1):engine.level.index);resetCamera()}
        }
        switch event.keyCode {case 123:camera-=40;case 124:camera+=40;default:break}
        clampCamera();onChange?();needsDisplay=true
    }
}
