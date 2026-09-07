import test from 'node:test';
import { mkdtempSync, writeFileSync, symlinkSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';
const { discover, validContract, fresh, reconcile, isMain } = await import(pathToFileURL(process.env.SONAR_DISCOVERY_MODULE));
const app = (name, repoURL) => ({metadata:{name}, spec:{source:{repoURL}}});
const workload = (name, owner, namespace='apps') => ({kind:'Deployment',metadata:{name,namespace,annotations:{'argocd.argoproj.io/tracking-id':`${owner}:apps/Deployment:${namespace}/${name}`}}});
test('discovers/deduplicates sources, excludes corp and reports missing owners', () => {
  const result=discover([
    workload('web','site'),workload('api','site'),workload('odoo','cluster','corp'),
    {kind:'Job',metadata:{name:'backup-1',namespace:'apps',ownerReferences:[{kind:'CronJob'}]}},
    workload('missing','unknown'),
  ],[app('site','http://gitlab.internal.example.com/team/site.git')],'team',['gitlab.internal.example.com']);
  assert.deepEqual(result.projects,['team/site']);assert.equal(result.errors.length,1);
});
test('rejects external repositories, embedded credentials and wrong groups', () => {
  for(const url of ['https://evil.example/team/site.git','https://gitlab.example/other/site.git','https://user:password@gitlab.example/team/site.git']) {
    const result=discover([workload('web','site')],[app('site',url)],'team',['gitlab.example']);
    assert.deepEqual(result.projects,[]);assert.ok(result.errors.length);
  }
});
test('rejects unsupported scan contracts and recognizes stale/invalid analysis',()=>{
  assert.ok(validContract({version:1,job:'02-quality',scanOnlyVariable:'SONAR_SCAN_ONLY'}));
  assert.ok(!validContract({version:2,job:'deploy',scanOnlyVariable:'RUN_ALL'}));
  assert.ok(!fresh('invalid',Date.now(),24));
  assert.ok(!fresh('2020-01-01',Date.now(),24));
  assert.ok(fresh(new Date().toISOString(),Date.now(),24));
});
function fixtures({missing=false,active=false,current=false,broken=false,throttled=false}={}) {
  const writes=[];const now=Date.parse('2026-09-07T12:00:00Z');
  const gitlab={
    async pages(path) {
      if(path.includes('/variables'))return missing?[]:[{key:'SONAR_TOKEN',environment_scope:'*'}];
      return active?[{id:3,status:'running'}]:throttled?[{id:4,source:'api',created_at:'2026-09-07T11:00:00Z'}]:[];
    },
    async call(method,path,body) {
      if(method!=='GET'){writes.push({service:'gitlab',method,path,body});return {id:17};}
      if(path.includes('sonar-project.properties'))return {content:Buffer.from('sonar.projectKey=team:site').toString('base64')};
      if(path.includes('.sonar-auto.json'))return broken?null:{content:Buffer.from(JSON.stringify({version:1,job:'quality',scanOnlyVariable:'SONAR_SCAN_ONLY'})).toString('base64')};
      return {id:1,name:'Site',visibility:'private',default_branch:'main'};
    },
  };
  const sonar={async call(method,path,body) {
    if(method!=='GET'){writes.push({service:'sonar',method,path,body});return {token:'analysis-secret'};}
    if(path.includes('projects/search'))return {components:missing?[]:[{key:'team:site',visibility:'private'}]};
    if(path.includes('get_binding'))return {alm:'gitlab'};
    if(path.includes('project_analyses'))return {analyses:current?[{date:'2026-09-07T10:00:00Z'}]:[]};
    throw Error(path);
  }};
  return {gitlab,sonar,now,writes};
}
test('provisions a private project and protected token, then requests scan-only CI',async()=>{
  const f=fixtures({missing:true});const errors=await reconcile({...f,projects:['team/site'],log:()=>{}});
  assert.deepEqual(errors,[]);
  assert.equal(f.writes.find(w=>w.path==='api/projects/create').body.visibility,'private');
  const token=f.writes.find(w=>w.path.endsWith('/variables')).body;
  assert.equal(token.masked,true);assert.equal(token.protected,true);
  const pipeline=f.writes.find(w=>w.path.endsWith('/pipeline')).body;
  assert.deepEqual(pipeline,{ref:'main',variables:[{key:'SONAR_SCAN_ONLY',value:'true'}]});
});
test('does not trigger current, active or recently attempted scans',async()=>{
  for(const opts of [{current:true},{active:true},{throttled:true}]){
    const f=fixtures(opts);assert.deepEqual(await reconcile({...f,projects:['team/site'],log:()=>{}}),[]);
    assert.ok(!f.writes.some(w=>w.path.endsWith('/pipeline')));
  }
});
test('missing CI contract is a visible error without triggering delivery',async()=>{
  const f=fixtures({broken:true});const errors=await reconcile({...f,projects:['team/site'],log:()=>{}});
  assert.equal(errors.length,1);assert.ok(!f.writes.some(w=>w.path.endsWith('/pipeline')));
});

test('runs its entrypoint through a Kubernetes ConfigMap symlink', () => {
  const dir=mkdtempSync(`${tmpdir()}/sonar-entry-`);
  try {
    writeFileSync(`${dir}/actual.mjs`, '');symlinkSync(`${dir}/actual.mjs`,`${dir}/discovery.mjs`);
    assert.equal(isMain(pathToFileURL(`${dir}/actual.mjs`).href,`${dir}/discovery.mjs`),true);
  } finally { rmSync(dir,{recursive:true,force:true}); }
});
