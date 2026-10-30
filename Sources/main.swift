import AppKit

func locateAssets()->URL {
    if let i=CommandLine.arguments.firstIndex(of:"--assets"),i+1<CommandLine.arguments.count {return URL(fileURLWithPath:CommandLine.arguments[i+1])}
    let bundle=Bundle.main.resourceURL?.appendingPathComponent("Assets")
    if let bundle=bundle,FileManager.default.fileExists(atPath:bundle.appendingPathComponent("game/catalog.json").path){return bundle}
    return URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("Assets")
}

final class AppDelegate:NSObject,NSApplicationDelegate {
    let assets:Assets;let engine:Engine;let audio:Audio
    var window:NSWindow!;var game:GameView!
    var timer:Timer?;var skillButtons:[NSButton]=[]
    let levels=NSPopUpButton();let stats=NSTextField(labelWithString:"")
    let pause=NSButton(title:"Pause",target:nil,action:nil)
    let fast=NSButton(title:"Vitesse ×1",target:nil,action:nil)
    let rate=NSSlider(value:1,minValue:1,maxValue:99,target:nil,action:nil)
    let rateLabel=NSTextField(labelWithString:"Débit 01")
    let musicButton=NSButton(checkboxWithTitle:"Musique",target:nil,action:nil)
    let effectsButton=NSButton(checkboxWithTitle:"Sons",target:nil,action:nil)
    init(assets:Assets) throws {
        self.assets=assets;engine=try Engine(assets:assets);audio=Audio(root:assets.root);super.init()
    }
    func applicationDidFinishLaunching(_ notification:Notification) {
        let menu=NSMenu();let appItem=NSMenuItem();menu.addItem(appItem)
        let appMenu=NSMenu();appItem.submenu=appMenu
        appMenu.addItem(withTitle:"À propos de Lemmings Mac",action:#selector(about),keyEquivalent:"")
        appMenu.addItem(.separator());appMenu.addItem(withTitle:"Quitter Lemmings Mac",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        let windowItem=NSMenuItem();menu.addItem(windowItem);let wm=NSMenu(title:"Fenêtre");windowItem.submenu=wm
        wm.addItem(withTitle:"Plein écran",action:#selector(NSWindow.toggleFullScreen(_:)),keyEquivalent:"f").keyEquivalentModifierMask=[.command,.control]
        NSApp.mainMenu=menu
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:1180,height:750),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title="Oh No! More Lemmings — Mac";window.minSize=NSSize(width:900,height:610);window.center()
        let content=NSView();content.wantsLayer=true;content.layer?.backgroundColor=NSColor.windowBackgroundColor.cgColor;window.contentView=content
        let top=NSStackView();top.orientation = .horizontal;top.spacing=12
        let title=NSTextField(labelWithString:"OH NO! MORE LEMMINGS");title.font = .systemFont(ofSize:17,weight:.heavy)
        for l in assets.catalog.levels {
            let done=UserDefaults.standard.bool(forKey:"completed.\(l.index)") ? "✓ ":""
            levels.addItem(withTitle:"\(done)\(l.rating) \(l.number) · \(l.title)")
        }
        levels.target=self;levels.action=#selector(selectLevel)
        levels.widthAnchor.constraint(greaterThanOrEqualToConstant:360).isActive=true
        top.addArrangedSubview(title);top.addArrangedSubview(levels)
        let retry=button("Recommencer",#selector(restart));let next=button("Suivant →",#selector(nextLevel))
        top.addArrangedSubview(retry);top.addArrangedSubview(next)
        stats.font = .monospacedSystemFont(ofSize:13,weight:.medium);stats.textColor = .secondaryLabelColor
        let skills=NSStackView();skills.orientation = .horizontal;skills.spacing=6;skills.distribution = .fillEqually
        for skill in Skill.allCases {
            let b=button(skill.label,#selector(selectSkill(_:)));b.tag=skill.rawValue;b.setButtonType(.toggle);b.bezelStyle = .regularSquare
            b.font = .monospacedSystemFont(ofSize:12,weight:.semibold);b.heightAnchor.constraint(equalToConstant:51).isActive=true;skills.addArrangedSubview(b);skillButtons.append(b)
        }
        let controls=NSStackView();controls.orientation = .horizontal;controls.spacing=12
        pause.target=self;pause.action=#selector(togglePause);fast.target=self;fast.action=#selector(toggleFast)
        rate.target=self;rate.action=#selector(rateChanged);rate.widthAnchor.constraint(equalToConstant:130).isActive=true
        rateLabel.font = .monospacedSystemFont(ofSize:12,weight:.regular)
        effectsButton.state = .on;effectsButton.target=self;effectsButton.action=#selector(toggleEffects)
        musicButton.state = .on;musicButton.target=self;musicButton.action=#selector(toggleMusic)
        for v in [pause,fast,rateLabel,rate,musicButton,effectsButton,button("Tout faire exploser",#selector(nuke))] as [NSView] {controls.addArrangedSubview(v)}
        let hint=NSTextField(labelWithString:"1–8 : compétence     Espace : pause     F : accélérer     R : recommencer     Flèches / molette / carte : défiler")
        hint.font = .systemFont(ofSize:11);hint.textColor = .secondaryLabelColor
        game=GameView(engine:engine);game.onChange={[weak self] in self?.refresh()}
        for v in [top,stats,skills,controls,hint,game!] as [NSView] {v.translatesAutoresizingMaskIntoConstraints=false;content.addSubview(v)}
        NSLayoutConstraint.activate([
            top.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:18),top.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-18),top.topAnchor.constraint(equalTo:content.topAnchor,constant:18),top.heightAnchor.constraint(equalToConstant:30),
            stats.leadingAnchor.constraint(equalTo:top.leadingAnchor),stats.topAnchor.constraint(equalTo:top.bottomAnchor,constant:10),
            skills.leadingAnchor.constraint(equalTo:top.leadingAnchor),skills.trailingAnchor.constraint(equalTo:top.trailingAnchor),skills.topAnchor.constraint(equalTo:stats.bottomAnchor,constant:12),
            controls.leadingAnchor.constraint(equalTo:top.leadingAnchor),controls.topAnchor.constraint(equalTo:skills.bottomAnchor,constant:10),
            hint.leadingAnchor.constraint(equalTo:top.leadingAnchor),hint.topAnchor.constraint(equalTo:controls.bottomAnchor,constant:10),
            game.leadingAnchor.constraint(equalTo:content.leadingAnchor),game.trailingAnchor.constraint(equalTo:content.trailingAnchor),game.topAnchor.constraint(equalTo:hint.bottomAnchor,constant:10),game.bottomAnchor.constraint(equalTo:content.bottomAnchor)
        ])
        engine.sound={[weak self] name in self?.audio.play(name)}
        window.makeKeyAndOrderFront(nil);window.makeFirstResponder(game);NSApp.activate(ignoringOtherApps:true)
        if let i=CommandLine.arguments.firstIndex(of:"--level"),i+1<CommandLine.arguments.count,let n=Int(CommandLine.arguments[i+1]){load(n)}
        audio.tune(engine.level.index);refresh()
        timer=Timer.scheduledTimer(withTimeInterval:1.0/17,repeats:true){[weak self] _ in self?.tick()}
        RunLoop.main.add(timer!,forMode:.eventTracking)
        if CommandLine.arguments.contains("--screenshot") {
            DispatchQueue.main.asyncAfter(deadline:.now()+0.5){[weak self] in self?.screenshot()}
        }
    }
    func button(_ title:String,_ action:Selector)->NSButton {let b=NSButton(title:title,target:self,action:action);b.bezelStyle = .rounded;return b}
    func tick(){for _ in 0..<(engine.fast ? 4:1){engine.step()};game.needsDisplay=true;refresh()}
    func refresh(){
        for (i,b) in skillButtons.enumerated(){let s=Skill(rawValue:i)!;b.title="\(i+1) \(s.symbol) \(s.label)\n\(engine.skills[i])";b.state=game.selection.rawValue==i ? .on:.off;b.contentTintColor=engine.skills[i]>0 ? nil:.secondaryLabelColor}
        let seconds=max(0,engine.timeLeft/17)
        stats.stringValue="\(engine.level.rating) \(engine.level.number)/20   ·   Sauvés \(engine.saved)/\(engine.level.required)   ·   Sortis \(engine.released)/\(engine.level.total)   ·   En jeu \(engine.active)   ·   \(seconds/60):\(String(format:"%02d",seconds%60))"
        pause.title=engine.paused ? "Reprendre":"Pause";fast.title=engine.fast ? "Vitesse ×4":"Vitesse ×1"
        rate.minValue=Double(engine.level.releaseRate);rate.doubleValue=Double(engine.releaseRate);rateLabel.stringValue=String(format:"Débit %02d",engine.releaseRate)
        levels.selectItem(at:engine.level.index)
    }
    func load(_ index:Int){do{try engine.load(index);game.resetCamera();audio.tune(index);refresh();game.needsDisplay=true;window.makeFirstResponder(game)}catch{showError(error)}}
    func showError(_ error:Error){let a=NSAlert(error:error);a.runModal()}
    @objc func selectLevel(){load(levels.indexOfSelectedItem)}
    @objc func restart(){load(engine.level.index)}
    @objc func nextLevel(){load((engine.level.index+1)%100)}
    @objc func selectSkill(_ sender:NSButton){game.selection=Skill(rawValue:sender.tag)!;refresh();window.makeFirstResponder(game)}
    @objc func togglePause(){engine.paused.toggle();refresh();window.makeFirstResponder(game)}
    @objc func toggleFast(){engine.fast.toggle();refresh();window.makeFirstResponder(game)}
    @objc func rateChanged(){engine.releaseRate=rate.integerValue;refresh()}
    @objc func toggleEffects(){audio.effects=effectsButton.state == .on}
    @objc func toggleMusic(){audio.musicEnabled=musicButton.state == .on;audio.tune(engine.level.index)}
    @objc func nuke(){engine.nuking=true;window.makeFirstResponder(game)}
    @objc func about(){let a=NSAlert();a.messageText="Oh No! More Lemmings — Mac";a.informativeText="Reconstruction native en Swift / AppKit à partir de votre disque Amiga.\n100 niveaux d’origine, terrain modifiable et huit compétences.\nVersion de développement : la fidélité des règles doit encore être comparée au jeu Amiga.\n\nJeu original : DMA Design / Psygnosis, 1991.";a.runModal()}
    func screenshot(){
        guard let v=window.contentView,let rep=v.bitmapImageRepForCachingDisplay(in:v.bounds) else{return}
        v.cacheDisplay(in:v.bounds,to:rep)
        if let data=rep.representation(using:.png,properties:[:]) {
            let i=CommandLine.arguments.firstIndex(of:"--screenshot")!
            let file=i+1<CommandLine.arguments.count ? CommandLine.arguments[i+1]:"screenshot.png"
            try? data.write(to:URL(fileURLWithPath:file));print("Screenshot: \(file)")
        }
        if CommandLine.arguments.contains("--quit-after-screenshot"){NSApp.terminate(nil)}
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{true}
}

do {
    let assets=try Assets(root:locateAssets())
    if CommandLine.arguments.contains("--self-test") {try runTests(assets);exit(0)}
    let app=NSApplication.shared;app.setActivationPolicy(.regular)
    let delegate=try AppDelegate(assets:assets);app.delegate=delegate;app.run()
} catch {fputs("Lemmings Mac : \(error)\n",stderr);exit(1)}
