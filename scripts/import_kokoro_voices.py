#!/usr/bin/env python3
"""Convert official Kokoro .pt voice tensors to SpaceMIT-compatible .npy files."""
from __future__ import annotations
import argparse, io, json, sys, time, urllib.error, urllib.request, zipfile
from pathlib import Path
import numpy as np

MODELS={"en":"hexgrad/Kokoro-82M","zh":"hexgrad/Kokoro-82M-v1.1-zh"}
# ModelScope mirrors the official voice tensors and is usually more reliable
# from mainland China. Hugging Face remains a fallback for portability.
MODELSCOPE_REPOS={"en":"AI-ModelScope/Kokoro-82M","zh":"AI-ModelScope/Kokoro-82M-v1.1-zh"}
REPOS={"en":["hexgrad/Kokoro-82M","mirror99/Kokoro-82M"],"zh":["hexgrad/Kokoro-82M-v1.1-zh","davidxifeng/Kokoro-82M-v1.1-zh"]}
VOICE_FALLBACK={
"en":"af_alloy af_aoede af_bella af_heart af_jessica af_kore af_nicole af_nova af_river af_sarah af_sky am_adam am_echo am_eric am_fenrir am_liam am_michael am_onyx am_puck am_santa bf_alice bf_emma bf_isabella bf_lily bm_daniel bm_fable bm_george bm_lewis ef_dora em_alex em_santa ff_siwis hf_alpha hf_beta hm_omega hm_psi if_sara im_nicola jf_alpha jf_gongitsune jf_nezumi jf_tebukuro jm_kumo pf_dora pm_alex pm_santa zf_xiaobei zf_xiaoni zf_xiaoxiao zf_xiaoyi zm_yunjian zm_yunxi zm_yunxia zm_yunyang".split(),
"zh":"af_maple af_sol bf_vale zf_001 zf_002 zf_003 zf_004 zf_005 zf_006 zf_007 zf_008 zf_017 zf_018 zf_019 zf_021 zf_022 zf_023 zf_024 zf_026 zf_027 zf_028 zf_032 zf_036 zf_038 zf_039 zf_040 zf_042 zf_043 zf_044 zf_046 zf_047 zf_048 zf_049 zf_051 zf_059 zf_060 zf_067 zf_070 zf_071 zf_072 zf_073 zf_074 zf_075 zf_076 zf_077 zf_078 zf_079 zf_083 zf_084 zf_085 zf_086 zf_087 zf_088 zf_090 zf_092 zf_093 zf_094 zf_099 zm_009 zm_010 zm_011 zm_012 zm_013 zm_014 zm_015 zm_016 zm_020 zm_025 zm_029 zm_030 zm_031 zm_033 zm_034 zm_035 zm_037 zm_041 zm_045 zm_050 zm_052 zm_053 zm_054 zm_055 zm_056 zm_057 zm_058 zm_061 zm_062 zm_063 zm_064 zm_065 zm_066 zm_068 zm_069 zm_080 zm_081 zm_082 zm_089 zm_091 zm_095 zm_096 zm_097 zm_098 zm_100".split()}

def download(url,retries,timeout=30):
    req=urllib.request.Request(url,headers={"User-Agent":"spacemit-kokoro-voice-import/1.0"}); last=None
    for i in range(retries+1):
        try:
            with urllib.request.urlopen(req,timeout=timeout) as r:return r.read()
        except (urllib.error.HTTPError,urllib.error.URLError,TimeoutError) as e:
            last=e
            if isinstance(e,urllib.error.HTTPError) and e.code not in (408,425,429,500,502,503,504):raise
            if i<retries:time.sleep(2**i)
    raise last

def tensor_from_pt(blob,voice):
    with zipfile.ZipFile(io.BytesIO(blob)) as z:
        names=[n for n in z.namelist() if n.endswith('/data/0')]
        if not names:raise ValueError(f'{voice}: no tensor storage')
        raw=z.read(names[0])
    if len(raw)%4:raise ValueError(f'{voice}: non-float32 payload')
    a=np.frombuffer(raw,dtype='<f4').copy()
    if not a.size or a.size%256:raise ValueError(f'{voice}: {a.size} floats, not divisible by 256')
    return a.reshape(a.size//256,1,256)

def load(path,voice):
    if path.suffix=='.pt':return tensor_from_pt(path.read_bytes(),voice)
    if path.suffix=='.npy':
        a=np.asarray(np.load(path,mmap_mode='r'),dtype=np.float32)
        if a.ndim==0 or a.shape[-1]!=256:raise ValueError(f'{path}: last dimension must be 256')
        return a
    a=np.fromfile(path,dtype='<f4')
    if not a.size or a.size%256:raise ValueError(f'{path}: raw floats not divisible by 256')
    return a.reshape(a.size//256,1,256)

def import_one(lang,voice,out,source_dirs,force,retries):
    target=out/f'{voice}.npy'
    if not force:
        # Reuse either supported checked-in representation and avoid creating
        # a duplicate .npy beside an existing .bin.
        existing=next((p for p in (target, out/f'{voice}.bin') if p.is_file()),None)
        if existing is not None:
            a=load(existing,voice)
            return {'voice':voice,'path':str(existing),'shape':list(a.shape),'status':'existing'}
    local=next((d/f'{voice}{ext}' for d in source_dirs for ext in ('.pt','.npy','.bin') if (d/f'{voice}{ext}').is_file()),None)
    if local:
        a=load(local,voice); status='converted-local'; source=str(local)
    else:
        last=None
        sources = [
            ("modelscope", f'https://modelscope.cn/api/v1/models/{MODELSCOPE_REPOS[lang]}/repo?Revision=master&FilePath=voices/{voice}.pt'),
        ] + [
            ("huggingface", f'https://huggingface.co/{repo}/resolve/main/voices/{voice}.pt?download=true')
            for repo in REPOS[lang]
        ]
        for source_kind, url in sources:
            try:
                a=tensor_from_pt(download(url,retries),voice)
                status=f'downloaded-{source_kind}'; source=url; break
            except Exception as e:
                last=e;print(f'  source {source_kind} failed for {voice}: {e}',file=sys.stderr)
        else:raise last
    tmp=target.with_name(target.name+'.tmp')
    with tmp.open('wb') as f:np.save(f,np.asarray(a,dtype=np.float32),allow_pickle=False)
    tmp.replace(target)
    return {'voice':voice,'path':str(target),'shape':list(a.shape),'status':status,'source':source}

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--language',choices=['en','zh','all'],default='all');p.add_argument('--output-dir',type=Path,default=Path('voices'));p.add_argument('--source-dir',type=Path,action='append',default=[]);p.add_argument('--voice',action='append');p.add_argument('--limit',type=int);p.add_argument('--force',action='store_true');p.add_argument('--keep-going',action='store_true');p.add_argument('--retries',type=int,default=2);a=p.parse_args()
    langs=['en','zh'] if a.language=='all' else [a.language];a.output_dir.mkdir(parents=True,exist_ok=True);mp=a.output_dir/'manifest.json';manifest={'source':'official Kokoro voice tensors','sources':['https://modelscope.cn/models/AI-ModelScope/Kokoro-82M','https://modelscope.cn/models/AI-ModelScope/Kokoro-82M-v1.1-zh','https://huggingface.co/hexgrad'],'format':'numpy float32, final dimension 256','languages':{}}
    if mp.exists():
        try:
            old=json.loads(mp.read_text())
            manifest['languages'].update(old.get('languages',{}))
            if old.get('sources'): manifest['sources']=list(dict.fromkeys(manifest['sources']+old['sources']))
        except (OSError,ValueError,TypeError):
            pass
    filt=set(a.voice or [])
    any_failed=False
    for lang in langs:
        names=[n for n in VOICE_FALLBACK[lang] if not filt or n in filt]
        names=names[:a.limit] if a.limit is not None else names
        out=a.output_dir/lang
        out.mkdir(parents=True,exist_ok=True)
        old_entries={x.get('voice'):x for x in manifest['languages'].get(lang,{}).get('voices',[]) if isinstance(x,dict) and x.get('voice')}
        results=[]
        failed=[]
        print(f'[{lang}] attempting {len(names)} voices from {MODELS[lang]}')
        for i,v in enumerate(names,1):
            try:
                r=import_one(lang,v,out,a.source_dir,a.force,max(0,a.retries))
                if r.get('status') == 'existing' and v in old_entries:
                    # Keep the current path/shape while preserving provenance
                    # from an earlier ModelScope/Hugging Face import.
                    previous=old_entries[v]
                    r={**previous, **r}
                    for key in ('status', 'source'):
                        if previous.get(key):
                            r[key]=previous[key]
                results.append(r)
                print(f"  {i}/{len(names)} {v}: {r['status']}")
            except Exception as e:
                failed.append({'voice':v,'error':str(e)})
                print(f'  {i}/{len(names)} {v}: FAILED ({e})',file=sys.stderr)
                if not a.keep_going: break
        # Keep the manifest complete when importing in batches: include all
        # existing .bin/.npy files, not only the voices in this invocation.
        for path in sorted(out.glob('*')):
            if path.suffix not in ('.bin','.npy') or path.stem in {r.get('voice') for r in results}:
                continue
            entry=old_entries.get(path.stem, {
                'voice':path.stem,
                'path':str(path),
                'shape':list(load(path,path.stem).shape),
                'status':'checked-in',
                'source':'SpaceMIT official model package or previous import'
            })
            results.append(entry)
        results.sort(key=lambda x:x.get('voice',''))
        manifest['languages'][lang]={
            'model':MODELS[lang],
            'available':len(results),
            'attempted':len(names),
            'count':len(results),
            'voices':results,
            'failed':failed
        }
        any_failed = any_failed or bool(failed)
        if failed and not a.keep_going:
            mp.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
            return 1
    mp.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    return 1 if any_failed else 0
if __name__=='__main__':raise SystemExit(main())
