#!/usr/bin/env python3
"""Generate original, self-contained KiCad 10 fixtures; no third-party library required."""
from pathlib import Path
import json
import uuid

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'examples/led-demo'
OUT.mkdir(parents=True, exist_ok=True)
def uid(label): return str(uuid.uuid5(uuid.NAMESPACE_URL, 'offline-eda-studio/' + label))
def write(path, text): (OUT / path).write_text(text, encoding='utf-8')
def js(path, data): write(path, json.dumps(data, ensure_ascii=False, indent=2) + '\n')
root_uuid = uid('schematic')
SY = 101.6
components = [('J1','Input',76.2,'Header2',['VCC','GND']), ('R1','330',106.68,'Axial2',['VCC','LED_A']), ('D1','LED',137.16,'Axial2',['LED_A','GND'])]

def symbol(name, connector=False):
    pins = [(-5.08,0,0),(-5.08,-5.08,0)] if connector else [(-5.08,0,0),(5.08,0,180)]
    pin_text = ''.join(f'(pin passive line (at {x} {y} {a}) (length 2.54) (name "{i}" (effects (font (size 1.27 1.27)))) (number "{i}" (effects (font (size 1.27 1.27)))))' for i,(x,y,a) in enumerate(pins,1))
    return f'''(symbol "{name}" (pin_names (offset 0)) (in_bom yes) (on_board yes)
      (property "Reference" "{'J' if connector else 'R'}" (at 0 3.81 0) (effects (font (size 1.27 1.27))))
      (property "Value" "{name.split(':')[-1]}" (at 0 -3.81 0) (effects (font (size 1.27 1.27))))
      (symbol "{name.split(':')[-1]}_0_1" (rectangle (start -2.54 1.27) (end 2.54 -6.35) (stroke (width 0) (type default)) (fill (type none))))
      (symbol "{name.split(':')[-1]}_1_1" {pin_text}))'''

write('OfflineEDA.kicad_sym', '(kicad_symbol_lib (version 20241209) (generator "kicad_symbol_editor") ' + symbol('TwoPin') + symbol('Connector',True) + ')\n')
write('sym-lib-table', '(sym_lib_table (version 7) (lib (name "OfflineEDA") (type "KiCad") (uri "${KIPRJMOD}/OfflineEDA.kicad_sym") (options "") (descr "Original two-pin demonstration symbols")))\n')
libdefs = symbol('OfflineEDA:TwoPin') + symbol('OfflineEDA:Connector',True)
instances = []; wires = []; labels = []
for ref, value, x, footprint, nets in components:
    connector = ref == 'J1'
    libid = 'OfflineEDA:Connector' if connector else 'OfflineEDA:TwoPin'
    sym_uuid = uid(ref)
    instances.append(f'''(symbol (lib_id "{libid}") (at {x} {SY} 0) (unit 1) (in_bom yes) (on_board yes) (dnp no) (uuid "{sym_uuid}")
      (property "Reference" "{ref}" (at {x} {SY-8.89} 0) (effects (font (size 1.27 1.27))))
      (property "Value" "{value}" (at {x} {SY-6.35} 0) (effects (font (size 1.27 1.27))))
      (property "Footprint" "OfflineEDA:{footprint}" (at {x} {SY} 0) (effects (font (size 1.27 1.27)) hide))
      (pin "1" (uuid "{uid(ref+'-p1')}")) (pin "2" (uuid "{uid(ref+'-p2')}"))
      (instances (project "design" (path "/{root_uuid}" (reference "{ref}") (unit 1)))))''')
    points = [(x-5.08,SY),(x-5.08,SY+5.08)] if connector else [(x-5.08,SY),(x+5.08,SY)]
    for i,((px,py),net) in enumerate(zip(points,nets)):
        direction = -1 if connector or i == 0 else 1
        ex = round(px + direction*5.08,2)
        wires.append(f'(wire (pts (xy {px:.2f} {py}) (xy {ex} {py})) (stroke (width 0) (type default)) (uuid "{uid(ref+str(i)+"wire")}"))')
        labels.append(f'(label "{net}" (at {ex} {py} 0) (effects (font (size 1.27 1.27)) (justify left bottom)) (uuid "{uid(ref+str(i)+"label")}"))')
write('design.kicad_sch', f'''(kicad_sch (version 20250114) (generator "eeschema")
 (uuid "{root_uuid}") (paper "A4")
 (title_block (title "Offline EDA LED demonstrator") (comment 1 "Original fixture. 3.3V input, verify LED polarity before assembly."))
 (lib_symbols {libdefs})
 {''.join(wires)} {''.join(labels)} {''.join(instances)}
 (sheet_instances (path "/" (page "1"))))\n''')

pretty = OUT / 'OfflineEDA.pretty'; pretty.mkdir(exist_ok=True)
def footprint(name, ref='REF**', value='', x=0,y=0, nets=None, path=None):
    connector = name == 'Header2'
    pads = [(0,0),(0,5.08)] if connector else [(-2.54,0),(2.54,0)]
    padtext = []
    for i,(px,py) in enumerate(pads,1):
        net = f'(net {nets[i-1][0]} "{nets[i-1][1]}")' if nets else ''
        kind = 'thru_hole circle' if connector else 'smd rect'
        drill = '(drill 1)' if connector else ''
        layers = '"*.Cu" "*.Mask"' if connector else '"F.Cu" "F.Paste" "F.Mask"'
        padtext.append(f'(pad "{i}" {kind} (at {px} {py}) (size 1.8 {1.8 if connector else 2}) {drill} (layers {layers}) {net} (uuid "{uid(ref+"pad"+str(i))}"))')
    courtyard = ('-1.3 -1.5','1.3 6.5') if connector else ('-3.8 -1.5','3.8 1.5')
    version = '' if nets else '(version 20241229) (generator "pcbnew")'
    return f'''(footprint "{'OfflineEDA:' if nets else ''}{name}" {version} (layer "F.Cu") (uuid "{uid(ref+'fp')}") (at {x} {y})
      (property "Reference" "{ref}" (at 0 -3 0) (layer "F.SilkS") (effects (font (size 1 1) (thickness 0.15))))
      (property "Value" "{value or name}" (at 0 -4.5 0) (layer "F.Fab") (effects (font (size 1 1) (thickness 0.15))))
      {'(path "'+path+'")' if path else ''} (attr {'through_hole' if connector else 'smd'})
      (fp_rect (start {courtyard[0]}) (end {courtyard[1]}) (stroke (width 0.05) (type default)) (fill none) (layer "F.CrtYd") (uuid "{uid(ref+'court')}"))
      {''.join(padtext)})'''
for name in ['Header2','Axial2']:
    (pretty/(name+'.kicad_mod')).write_text(footprint(name)+'\n')
write('fp-lib-table', '(fp_lib_table (version 7) (lib (name "OfflineEDA") (type "KiCad") (uri "${KIPRJMOD}/OfflineEDA.pretty") (options "") (descr "Original demonstration footprints")))\n')
netmap = {'VCC':1,'LED_A':2,'GND':3}
fps = []
for (ref,value,_,name,nets),(x,y) in zip(components,[(10,10),(25,10),(40,10)]):
    fps.append(footprint(name,ref,value,x,y,[(netmap[n],"/"+n) for n in nets], '/'+root_uuid+'/'+uid(ref)))
segments = [(10,10,22.46,10,1),(27.54,10,37.46,10,2),(10,15.08,10,19,3),(10,19,42.54,19,3),(42.54,19,42.54,10,3)]
tracks = ''.join(f'(segment (start {x1} {y1}) (end {x2} {y2}) (width 0.4) (layer "F.Cu") (net {net}) (uuid "{uid("track"+str(i))}"))' for i,(x1,y1,x2,y2,net) in enumerate(segments))
outline = ''.join(f'(gr_line (start {x1} {y1}) (end {x2} {y2}) (stroke (width 0.05) (type default)) (layer "Edge.Cuts") (uuid "{uid("edge"+str(i))}"))' for i,(x1,y1,x2,y2) in enumerate([(5,5,48,5),(48,5,48,23),(48,23,5,23),(5,23,5,5)]))
write('design.kicad_pcb', f'''(kicad_pcb (version 20241229) (generator "pcbnew")
 (general (thickness 1.6)) (paper "A4")
 (layers (0 "F.Cu" signal) (2 "B.Cu" signal) (9 "F.Adhes" user "F.Adhesive") (11 "B.Adhes" user "B.Adhesive") (13 "F.Paste" user) (15 "B.Paste" user) (5 "F.SilkS" user "F.Silkscreen") (7 "B.SilkS" user "B.Silkscreen") (1 "F.Mask" user) (3 "B.Mask" user) (25 "Edge.Cuts" user) (31 "F.CrtYd" user "F.Courtyard") (33 "B.CrtYd" user "B.Courtyard") (35 "F.Fab" user) (37 "B.Fab" user))
 (setup (pad_to_mask_clearance 0))
 (net 0 "") (net 1 "/VCC") (net 2 "/LED_A") (net 3 "/GND")
 {''.join(fps)} {tracks} {outline})\n''')
js('design.kicad_pro', {'meta':{'filename':'design.kicad_pro','version':1}, 'board':{'design_settings':{'rules':{'min_clearance':0.2,'min_track_width':0.2,'min_copper_edge_clearance':0.3}}}, 'schematic':{}, 'net_settings':{'classes':[{'name':'Default','clearance':0.2,'track_width':0.4,'via_diameter':0.8,'via_drill':0.4}]}})
js('eda-project.json',{'schemaVersion':1,'name':'LED · 双层板示例','projectFile':'design.kicad_pro','schematicFile':'design.kicad_sch','boardFile':'design.kicad_pcb','partsFile':'parts.json','harnessFile':'harness.json'})
js('parts.json', [dict(reference=ref,value=value,footprint='OfflineEDA:'+fp,mpn='',manufacturer='',unitPrice=0,dnp=False) for ref,value,_,fp,_ in components])
js('harness.json',{'schemaVersion':1,'connectors':[{'id':'J1','pins':2,'partNumber':'demo-input'},{'id':'J2','pins':2,'partNumber':'demo-supply'}],'wires':[{'id':'W1','from':{'connector':'J1','pin':1},'to':{'connector':'J2','pin':1},'net':'VCC','lengthMM':150,'awg':24,'color':'red'},{'id':'W2','from':{'connector':'J1','pin':2},'to':{'connector':'J2','pin':2},'net':'GND','lengthMM':150,'awg':24,'color':'black'}]})
write('README.md', '# 自包含 LED 示例\n\n原始演示数据，符号与封装均由本仓库生成，不依赖外部元件库。J1.1 为 3.3 V 输入，J1.2 为地；R1 330 Ω 与 D1 串联。图形是通用两引脚演示符号，未替代真实 LED 符号及器件电气模型。板上封装、极性、电流与器件料号必须按实际采购器件重新设计和验证，不可直接投产。线束数据为独立点对点示例，J2 是外部电源连接器。采购单价 0 表示未录入报价。\n')
print(OUT)
