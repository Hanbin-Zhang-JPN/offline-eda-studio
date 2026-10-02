#!/usr/bin/env python3
"""Real KiCad tests. Requires a supported local engine; never substitutes a fake pass."""
import argparse, json, os, subprocess, tempfile, shutil, hashlib, time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(); p.add_argument('--eda',default=str(ROOT/'.build/debug/eda')); p.add_argument('--report',default=str(ROOT/'reports/integration.json')); args=p.parse_args()
EDA=str(Path(args.eda).resolve())
report={'schemaVersion':1,'platform':os.uname().machine,'engine':None,'tests':[],'scope':'Single self-contained two-layer fixture and negative gates; not full professional feature acceptance.'}
def run(*cmd, ok=True):
    start=time.monotonic()
    result=subprocess.run([EDA,*map(str,cmd)],text=True,capture_output=True,timeout=240)
    if ok and result.returncode != 0: raise AssertionError(result.stdout+'\n'+result.stderr)
    return result,time.monotonic()-start

def record(name,detail,duration=0): report['tests'].append({'name':name,'passed':True,'detail':detail,'seconds':round(duration,3)})
try:
    doctor,_=run('doctor'); report['engine']=doctor.stdout.splitlines()[0]
    with tempfile.TemporaryDirectory(prefix='eda-integration-') as temp:
        base=Path(temp); project=base/'中文 project with spaces'
        shutil.copytree(ROOT/'examples/led-demo',project,ignore=shutil.ignore_patterns('outputs','.eda-snapshots'))
        run('inspect',project); record('project-open','Unicode and spaces in paths')
        snap,_=run('snapshot',project,'integration snapshot'); snapshot=Path(snap.stdout.strip())
        run('verify-snapshot',snapshot); record('snapshot-integrity','SHA-256 revalidation')
        run('bom',project,base/'planning.csv'); run('harness',project,base/'harness.csv')
        record('offline-data-exports','Planning BOM and point-to-point wire list')
        for job in ['erc','drc','gerbers','drill','positions','step','boardSVG','schematicPDF','netlist','schematicBOM','ipc2581','odb']:
            out=base/job; _,seconds=run('job',project,job,out)
            files=[x for x in out.rglob('*') if x.is_file()]
            assert files and all(x.stat().st_size for x in files),job+' missing output'
            record('job-'+job,f'{len(files)} nonempty files; export readability except reports needs independent production acceptance',seconds)
        released,seconds=run('release',project,'--step'); release=Path(released.stdout.strip())
        manifest=json.loads((release/'release.json').read_text()); assert manifest['status']=='passed'
        for f in manifest['artifacts']:
            data=(release/'artifacts'/f['path']).read_bytes()
            assert hashlib.sha256(data).hexdigest()==f['sha256'] and len(data)==f['bytes']
        record('manufacturing-passed','ERC+DRC+schematic parity gate, original sources, output hashes including STEP',seconds)
        # Positive fixture copied from project excluding earlier releases.
        bad=base/'bad-board'; shutil.copytree(project,bad,ignore=shutil.ignore_patterns('outputs','.eda-snapshots'))
        board=bad/'design.kicad_pcb'; text=board.read_text()
        # Remove first track using balanced-expression boundaries.
        start=text.index('(segment '); depth=0; end=start
        for i in range(start,len(text)):
            depth += (text[i]=='(')-(text[i]==')')
            if depth==0: end=i+1; break
        board.write_text(text[:start]+text[end:])
        failed,_=run('release',bad,ok=False); assert failed.returncode != 0
        out=bad/'outputs'; assert not list(out.glob('release-*'))
        failures=list(out.glob('failed-*')); assert len(failures)==1
        failure=json.loads((failures[0]/'release.json').read_text()); assert failure['status']=='failed'
        assert failure['commands'][-1]['exitCode'] != 0
        record('unconnected-board-blocked','Removed track prevents manufacturing release and preserves failure report')
        # Reject four-layer copper instead of silently omitting inner copper.
        multilayer=base/'four-layer'; shutil.copytree(ROOT/'examples/led-demo',multilayer,ignore=shutil.ignore_patterns('outputs','.eda-snapshots'))
        pcb=multilayer/'design.kicad_pcb'; pcb.write_text(pcb.read_text().replace('(2 "B.Cu" signal)','(4 "In1.Cu" signal) (6 "In2.Cu" signal) (2 "B.Cu" signal)'))
        result,_=run('release',multilayer,ok=False); assert result.returncode !=0 and '双层' in result.stderr
        record('multilayer-release-blocked','v0.1 never exports incomplete inner copper')
        source=project/'design.kicad_sch'; snap_source=snapshot/'source/design.kicad_sch'
        snap_source.write_text(snap_source.read_text()+'\n; modified\n')
        result,_=run('verify-snapshot',snapshot,ok=False); assert result.returncode != 0
        record('tampered-snapshot-blocked','Changed file rejected')
    report['passed']=True
except Exception as error:
    report['passed']=False; report['failure']=str(error)
finally:
    Path(args.report).parent.mkdir(parents=True,exist_ok=True)
    Path(args.report).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'passed':report['passed'],'tests':len(report['tests']),'report':args.report},ensure_ascii=False))
if not report['passed']: raise SystemExit(report.get('failure','integration failed'))
