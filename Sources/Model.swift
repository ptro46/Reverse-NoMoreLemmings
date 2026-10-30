import AppKit
import ImageIO

struct Catalog: Decodable { let width, height: Int; let styles: [Style]; let sprites: [String: Sprite]; let levels: [Level] }
struct Style: Decodable { let palette: [[Int]]; let terrain: [Tile?]; let objects: [ObjectArt?] }
struct Tile: Decodable { let image: String; let width,height: Int }
struct ObjectArt: Decodable { let frames: [String]; let width,height,kind,trigger,triggerX,triggerY,triggerWidth,triggerHeight,sound: Int }
struct Sprite: Decodable { let width,height: Int; let frames: [[String]] }
struct Placement: Decodable { let x,y,id,flags: Int }
struct TerrainPlacement: Decodable { let x,y,id: Int; let upsideDown,erase,behind: Bool }
struct Steel: Decodable { let x,y,width,height: Int }
struct Level: Decodable {
    let index,sourceIndex: Int
    let rating: String; let number: Int; let title: String
    let releaseRate,total,required,minutes: Int
    let skills: [Int]; let cameraX,style: Int
    let objects: [Placement]; let terrain: [TerrainPlacement]; let steel: [Steel]
}
enum Skill: Int, CaseIterable {
    case climb, float, bomb, block, build, bash, mine, dig
    var label: String { ["Grimpeur", "Parachute", "Bombe", "Bloqueur", "Constructeur", "Tunnelier", "Mineur", "Foreur"][rawValue] }
    var symbol: String { ["↑", "☂", "✹", "↔", "⌁", "→", "↘", "↓"][rawValue] }
}
final class Assets {
    let root: URL; let catalog: Catalog
    private var images: [String:NSImage] = [:]
    init(root: URL) throws {
        self.root=root
        catalog=try JSONDecoder().decode(Catalog.self,from:Data(contentsOf:root.appendingPathComponent("game/catalog.json")))
    }
    func image(_ name: String) -> NSImage? {
        if let im=images[name] { return im }
        guard let im=NSImage(contentsOf:root.appendingPathComponent("game/"+name)) else { return nil }
        images[name]=im; return im
    }
    func rgba(_ name: String) throws -> [UInt8] {
        let url=root.appendingPathComponent("game/"+name)
        guard let source=CGImageSourceCreateWithURL(url as CFURL,nil), let cg=CGImageSourceCreateImageAtIndex(source,0,nil) else { throw NSError(domain:"Assets",code:1) }
        var pixels=[UInt8](repeating:0,count:cg.width*cg.height*4)
        let ok=pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let ctx=CGContext(data:bytes.baseAddress,width:cg.width,height:cg.height,bitsPerComponent:8,bytesPerRow:cg.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue|CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            ctx.draw(cg,in:CGRect(x:0,y:0,width:cg.width,height:cg.height));return true
        }
        if !ok { throw NSError(domain:"Assets",code:2) }
        return pixels
    }
}
